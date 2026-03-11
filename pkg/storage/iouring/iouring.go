package iouring

import (
	"errors"
	"fmt"
	"runtime"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

// Syscall numbers for io_uring (x86_64)
const (
	SYS_IO_URING_SETUP    = 425
	SYS_IO_URING_ENTER    = 426
	SYS_IO_URING_REGISTER = 427
)

// Constants for io_uring offsets
const (
	IORING_OFF_SQ_RING = 0x0
	IORING_OFF_CQ_RING = 0x8000000
	IORING_OFF_SQES    = 0x10000000
)

// Constants for io_uring flags
const (
	IORING_FEAT_SINGLE_MMAP = 1 << 0
)

// io_uring_params structure
type IOUringParams struct {
	SQEntries    uint32
	CQEntries    uint32
	Flags        uint32
	SQThreadCPU  uint32
	SQThreadIdle uint32
	Features     uint32
	Reserved     [4]uint32
	SQOff        SQRingOffsets
	CQOff        CQRingOffsets
}

// SQRingOffsets structure
type SQRingOffsets struct {
	Head        uint32
	Tail        uint32
	RingMask    uint32
	RingEntries uint32
	Flags       uint32
	Dropped     uint32
	Array       uint32
	Reserved    [3]uint32
}

// CQRingOffsets structure
type CQRingOffsets struct {
	Head        uint32
	Tail        uint32
	RingMask    uint32
	RingEntries uint32
	Overflow    uint32
	CQEs        uint32
	Reserved    [4]uint32
}

// IOUring represents an io_uring instance
type IOUring struct {
	ring     *Ring
	sqe      *SubmissionQueue
	cqe      *CompletionQueue
	mu       sync.Mutex
	closed   bool
	requests map[uint64]*IORequest
	nextID   uint64
}

// Ring represents the io_uring ring structure
type Ring struct {
	fd        int
	features  uint32
	flags     uint32
	sqRingMem []byte
	cqRingMem []byte
	sqesMem   []byte
	params    *IOUringParams
}

// SubmissionQueue represents the submission queue
type SubmissionQueue struct {
	head    *uint32
	tail    *uint32
	mask    uint32
	entries uint32
	flags   *uint32
	dropped *uint32
	array   []uint32
	sqes    []SubmissionQueueEntry
}

// CompletionQueue represents the completion queue
type CompletionQueue struct {
	head     *uint32
	tail     *uint32
	mask     uint32
	entries  uint32
	overflow *uint32
	cqes     []CompletionQueueEntry
}

// SubmissionQueueEntry represents a submission queue entry
type SubmissionQueueEntry struct {
	opcode      uint8
	flags       uint8
	ioprio      uint16
	fd          int32
	offset      uint64
	addr        uint64
	len         uint32
	opcodeFlags uint32
	userData    uint64
	bufIndex    uint16
	personality uint16
	splicefd    int32
	pad         [2]uint64
}

// CompletionQueueEntry represents a completion queue entry
type CompletionQueueEntry struct {
	userData uint64
	res      int32
	flags    uint32
}

// Forward declarations to avoid circular imports
type IORequest struct {
	ID       uint64
	Type     IOType
	FD       int
	Offset   int64
	Buffer   []byte
	Callback func(*IOCompletion)
	UserData interface{}
}

type IOCompletion struct {
	Request *IORequest
	Result  int
	Error   error
}

type IOType int

const (
	IOTypeRead IOType = iota
	IOTypeWrite
)

// io_uring opcodes
const (
	IORING_OP_NOP = iota
	IORING_OP_READV
	IORING_OP_WRITEV
	IORING_OP_FSYNC
	IORING_OP_READ_FIXED
	IORING_OP_WRITE_FIXED
	IORING_OP_POLL_ADD
	IORING_OP_POLL_REMOVE
	IORING_OP_SYNC_FILE_RANGE
	IORING_OP_SENDMSG
	IORING_OP_RECVMSG
	IORING_OP_TIMEOUT
	IORING_OP_TIMEOUT_REMOVE
	IORING_OP_ACCEPT
	IORING_OP_ASYNC_CANCEL
	IORING_OP_LINK_TIMEOUT
	IORING_OP_CONNECT
	IORING_OP_FALLOCATE
	IORING_OP_OPENAT
	IORING_OP_CLOSE
	IORING_OP_FILES_UPDATE
	IORING_OP_STATX
	IORING_OP_READ
	IORING_OP_WRITE
)

// NewIOUring creates a new io_uring instance
func NewIOUring(entries uint32) (*IOUring, error) {
	// Check if io_uring is available
	if !isIOUringAvailable() {
		return nil, errors.New("io_uring not available on this system")
	}

	ring, err := setupIOUring(entries)
	if err != nil {
		return nil, fmt.Errorf("failed to setup io_uring: %w", err)
	}

	sqe, err := setupSubmissionQueue(ring)
	if err != nil {
		return nil, fmt.Errorf("failed to setup submission queue: %w", err)
	}

	cqe, err := setupCompletionQueue(ring)
	if err != nil {
		return nil, fmt.Errorf("failed to setup completion queue: %w", err)
	}

	return &IOUring{
		ring:     ring,
		sqe:      sqe,
		cqe:      cqe,
		requests: make(map[uint64]*IORequest),
	}, nil
}

// isIOUringAvailable checks if io_uring is available
func isIOUringAvailable() bool {
	// Check if we're on Linux
	if runtime.GOOS != "linux" {
		return false
	}

	// Try to create a minimal io_uring to test availability
	params := &IOUringParams{
		SQEntries: 1,
		CQEntries: 1,
	}

	fd, _, errno := syscall.Syscall(SYS_IO_URING_SETUP, 1, uintptr(unsafe.Pointer(params)), 0)
	if errno != 0 {
		return false
	}

	syscall.Close(int(fd))
	return true
}

// setupIOUring initializes the io_uring
func setupIOUring(entries uint32) (*Ring, error) {
	params := &IOUringParams{
		SQEntries: entries,
		CQEntries: entries * 2, // Common practice to have CQ larger than SQ
	}

	fd, _, errno := syscall.Syscall(SYS_IO_URING_SETUP, uintptr(entries), uintptr(unsafe.Pointer(params)), 0)
	if errno != 0 {
		return nil, fmt.Errorf("io_uring_setup failed: %v", errno)
	}

	ring := &Ring{
		fd:       int(fd),
		features: params.Features,
		flags:    params.Flags,
		params:   params,
	}

	// Map submission queue ring
	sqRingSize := int(params.SQOff.Array + params.SQEntries*4)
	cqRingSize := int(params.CQOff.CQEs + params.CQEntries*uint32(unsafe.Sizeof(CompletionQueueEntry{})))

	var err error

	// Check if single mmap is supported
	if params.Features&IORING_FEAT_SINGLE_MMAP != 0 {
		if cqRingSize > sqRingSize {
			sqRingSize = cqRingSize
		}
		cqRingSize = sqRingSize
	}

	ring.sqRingMem, err = mmapRing(int(fd), IORING_OFF_SQ_RING, sqRingSize)
	if err != nil {
		syscall.Close(int(fd))
		return nil, fmt.Errorf("failed to mmap submission queue ring: %w", err)
	}

	if params.Features&IORING_FEAT_SINGLE_MMAP != 0 {
		ring.cqRingMem = ring.sqRingMem
	} else {
		ring.cqRingMem, err = mmapRing(int(fd), IORING_OFF_CQ_RING, cqRingSize)
		if err != nil {
			syscall.Munmap(ring.sqRingMem)
			syscall.Close(int(fd))
			return nil, fmt.Errorf("failed to mmap completion queue ring: %w", err)
		}
	}

	// Map submission queue entries
	sqeSize := int(params.SQEntries * uint32(unsafe.Sizeof(SubmissionQueueEntry{})))
	ring.sqesMem, err = mmapRing(int(fd), IORING_OFF_SQES, sqeSize)
	if err != nil {
		if params.Features&IORING_FEAT_SINGLE_MMAP == 0 {
			syscall.Munmap(ring.cqRingMem)
		}
		syscall.Munmap(ring.sqRingMem)
		syscall.Close(int(fd))
		return nil, fmt.Errorf("failed to mmap submission queue entries: %w", err)
	}

	return ring, nil
}

// mmapRing maps a ring buffer
func mmapRing(fd int, offset int64, size int) ([]byte, error) {
	data, err := syscall.Mmap(fd, offset, size, syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
	if err != nil {
		return nil, err
	}
	return data, nil
}

// setupSubmissionQueue sets up the submission queue
func setupSubmissionQueue(ring *Ring) (*SubmissionQueue, error) {
	params := ring.params

	// Get pointers to ring fields
	head := (*uint32)(unsafe.Pointer(&ring.sqRingMem[params.SQOff.Head]))
	tail := (*uint32)(unsafe.Pointer(&ring.sqRingMem[params.SQOff.Tail]))
	mask := *(*uint32)(unsafe.Pointer(&ring.sqRingMem[params.SQOff.RingMask]))
	entries := *(*uint32)(unsafe.Pointer(&ring.sqRingMem[params.SQOff.RingEntries]))
	flags := (*uint32)(unsafe.Pointer(&ring.sqRingMem[params.SQOff.Flags]))
	dropped := (*uint32)(unsafe.Pointer(&ring.sqRingMem[params.SQOff.Dropped]))

	// Get array pointer
	arrayPtr := uintptr(unsafe.Pointer(&ring.sqRingMem[params.SQOff.Array]))
	array := (*[1024]uint32)(unsafe.Pointer(arrayPtr))[:params.SQEntries:params.SQEntries]

	// Get SQEs
	sqesPtr := uintptr(unsafe.Pointer(&ring.sqesMem[0]))
	sqes := (*[1024]SubmissionQueueEntry)(unsafe.Pointer(sqesPtr))[:params.SQEntries:params.SQEntries]

	return &SubmissionQueue{
		head:    head,
		tail:    tail,
		mask:    mask,
		entries: entries,
		flags:   flags,
		dropped: dropped,
		array:   array,
		sqes:    sqes,
	}, nil
}

// setupCompletionQueue sets up the completion queue
func setupCompletionQueue(ring *Ring) (*CompletionQueue, error) {
	params := ring.params

	// Get pointers to ring fields
	head := (*uint32)(unsafe.Pointer(&ring.cqRingMem[params.CQOff.Head]))
	tail := (*uint32)(unsafe.Pointer(&ring.cqRingMem[params.CQOff.Tail]))
	mask := *(*uint32)(unsafe.Pointer(&ring.cqRingMem[params.CQOff.RingMask]))
	entries := *(*uint32)(unsafe.Pointer(&ring.cqRingMem[params.CQOff.RingEntries]))
	overflow := (*uint32)(unsafe.Pointer(&ring.cqRingMem[params.CQOff.Overflow]))

	// Get CQEs
	cqesPtr := uintptr(unsafe.Pointer(&ring.cqRingMem[params.CQOff.CQEs]))
	cqes := (*[1024]CompletionQueueEntry)(unsafe.Pointer(cqesPtr))[:params.CQEntries:params.CQEntries]

	return &CompletionQueue{
		head:     head,
		tail:     tail,
		mask:     mask,
		entries:  entries,
		overflow: overflow,
		cqes:     cqes,
	}, nil
}

// ReadAsync submits an asynchronous read request
func (io *IOUring) ReadAsync(fd int, offset int64, buf []byte) (*IORequest, error) {
	io.mu.Lock()
	defer io.mu.Unlock()

	if io.closed {
		return nil, errors.New("io_uring is closed")
	}

	io.nextID++
	req := &IORequest{
		ID:     io.nextID,
		Type:   IOTypeRead,
		FD:     fd,
		Offset: offset,
		Buffer: buf,
	}

	io.requests[req.ID] = req
	return req, nil
}

// WriteAsync submits an asynchronous write request
func (io *IOUring) WriteAsync(fd int, offset int64, buf []byte) (*IORequest, error) {
	io.mu.Lock()
	defer io.mu.Unlock()

	if io.closed {
		return nil, errors.New("io_uring is closed")
	}

	io.nextID++
	req := &IORequest{
		ID:     io.nextID,
		Type:   IOTypeWrite,
		FD:     fd,
		Offset: offset,
		Buffer: buf,
	}

	io.requests[req.ID] = req
	return req, nil
}

// Submit submits I/O requests to the kernel
func (io *IOUring) Submit(requests []*IORequest) error {
	io.mu.Lock()
	defer io.mu.Unlock()

	if io.closed {
		return errors.New("io_uring is closed")
	}

	if len(requests) == 0 {
		return nil
	}

	// Prepare SQEs
	tail := *io.sqe.tail
	for _, req := range requests {
		index := tail & io.sqe.mask
		sqe := &io.sqe.sqes[index]

		sqe.userData = req.ID
		sqe.fd = int32(req.FD)
		sqe.addr = uint64(uintptr(unsafe.Pointer(&req.Buffer[0])))
		sqe.len = uint32(len(req.Buffer))
		sqe.offset = uint64(req.Offset)

		if req.Type == IOTypeRead {
			sqe.opcode = IORING_OP_READ
		} else {
			sqe.opcode = IORING_OP_WRITE
		}

		io.sqe.array[index] = index
		tail++
	}

	// Update tail with memory barrier
	*io.sqe.tail = tail

	// Submit to kernel
	_, _, errno := syscall.Syscall6(SYS_IO_URING_ENTER,
		uintptr(io.ring.fd),
		uintptr(len(requests)),
		0,
		0,
		0,
		0)

	if errno != 0 {
		return fmt.Errorf("io_uring_enter failed: %v", errno)
	}

	return nil
}

// Poll polls for completed I/O operations
func (io *IOUring) Poll(timeout time.Duration) ([]*IOCompletion, error) {
	io.mu.Lock()
	defer io.mu.Unlock()

	if io.closed {
		return nil, errors.New("io_uring is closed")
	}

	var completions []*IOCompletion
	head := *io.cqe.head
	tail := *io.cqe.tail

	// Process available completions
	for head != tail {
		index := head & io.cqe.mask
		cqe := &io.cqe.cqes[index]

		req, exists := io.requests[cqe.userData]
		if exists {
			delete(io.requests, cqe.userData)

			completion := &IOCompletion{
				Request: req,
				Result:  int(cqe.res),
			}

			if cqe.res < 0 {
				completion.Error = syscall.Errno(-cqe.res)
			}

			completions = append(completions, completion)
		}

		head++
	}

	// Update head
	*io.cqe.head = head

	return completions, nil
}

// Close closes the io_uring instance
func (io *IOUring) Close() error {
	io.mu.Lock()
	defer io.mu.Unlock()

	if io.closed {
		return nil
	}

	io.closed = true

	// Unmap memory
	if io.ring.sqesMem != nil {
		syscall.Munmap(io.ring.sqesMem)
	}
	if io.ring.cqRingMem != nil && io.ring.params.Features&IORING_FEAT_SINGLE_MMAP == 0 {
		syscall.Munmap(io.ring.cqRingMem)
	}
	if io.ring.sqRingMem != nil {
		syscall.Munmap(io.ring.sqRingMem)
	}

	if io.ring.fd >= 0 {
		syscall.Close(io.ring.fd)
	}

	return nil
}
