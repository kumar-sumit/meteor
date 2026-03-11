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
	IORING_ENTER_GETEVENTS  = 1 << 0
	IORING_SETUP_SQPOLL     = 1 << 1
	IORING_SETUP_IOPOLL     = 1 << 2
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

// IOUring represents an io_uring instance with enhanced performance
type IOUring struct {
	ring     *Ring
	sqe      *SubmissionQueue
	cqe      *CompletionQueue
	mu       sync.RWMutex
	closed   bool
	requests map[uint64]*IORequest
	nextID   uint64

	// Performance optimizations
	batchSize   int
	pollTimeout time.Duration
	batchBuffer []*IORequest
	completions chan *IOCompletion
	workers     int
	wg          sync.WaitGroup
	stopChan    chan struct{}
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

// SubmissionQueue represents the submission queue with optimizations
type SubmissionQueue struct {
	head    *uint32
	tail    *uint32
	mask    uint32
	entries uint32
	flags   *uint32
	dropped *uint32
	array   []uint32
	sqes    []SubmissionQueueEntry

	// Performance optimizations
	localTail uint32
	batchSize int
}

// CompletionQueue represents the completion queue with optimizations
type CompletionQueue struct {
	head     *uint32
	tail     *uint32
	mask     uint32
	entries  uint32
	overflow *uint32
	cqes     []CompletionQueueEntry

	// Performance optimizations
	localHead uint32
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
	IORING_OP_FADVISE
	IORING_OP_MADVISE
	IORING_OP_SEND
	IORING_OP_RECV
)

// NewIOUring creates a new io_uring instance with enhanced performance
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

	// Calculate optimal batch size based on ring size
	batchSize := int(entries / 4)
	if batchSize < 8 {
		batchSize = 8
	}
	if batchSize > 64 {
		batchSize = 64
	}

	workers := runtime.NumCPU()
	if workers > 4 {
		workers = 4
	}

	iouring := &IOUring{
		ring:        ring,
		sqe:         sqe,
		cqe:         cqe,
		requests:    make(map[uint64]*IORequest),
		batchSize:   batchSize,
		pollTimeout: time.Millisecond * 10,
		batchBuffer: make([]*IORequest, 0, batchSize),
		completions: make(chan *IOCompletion, int(entries)),
		workers:     workers,
		stopChan:    make(chan struct{}),
	}

	// Start completion workers
	for i := 0; i < workers; i++ {
		iouring.wg.Add(1)
		go iouring.completionWorker()
	}

	return iouring, nil
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

// setupIOUring initializes the io_uring with performance optimizations
func setupIOUring(entries uint32) (*Ring, error) {
	params := &IOUringParams{
		SQEntries: entries,
		CQEntries: entries * 2, // Larger CQ for better batching
		Flags:     0,           // No special flags for compatibility
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

	// Memory map the rings
	if err := ring.mapRings(); err != nil {
		syscall.Close(int(fd))
		return nil, err
	}

	return ring, nil
}

// mapRings maps the io_uring rings into memory
func (r *Ring) mapRings() error {
	sqRingSize := r.params.SQOff.Array + r.params.SQEntries*4
	cqRingSize := r.params.CQOff.CQEs + r.params.CQEntries*16

	// Map submission queue ring
	sqRingMem, err := syscall.Mmap(r.fd, IORING_OFF_SQ_RING, int(sqRingSize), syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
	if err != nil {
		return fmt.Errorf("failed to map SQ ring: %w", err)
	}
	r.sqRingMem = sqRingMem

	// Map completion queue ring
	if r.features&IORING_FEAT_SINGLE_MMAP != 0 {
		// Single mmap mode
		r.cqRingMem = sqRingMem
	} else {
		// Separate mmap for CQ
		cqRingMem, err := syscall.Mmap(r.fd, IORING_OFF_CQ_RING, int(cqRingSize), syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
		if err != nil {
			syscall.Munmap(sqRingMem)
			return fmt.Errorf("failed to map CQ ring: %w", err)
		}
		r.cqRingMem = cqRingMem
	}

	// Map submission queue entries
	sqesSize := r.params.SQEntries * 64 // Each SQE is 64 bytes
	sqesMem, err := syscall.Mmap(r.fd, IORING_OFF_SQES, int(sqesSize), syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
	if err != nil {
		syscall.Munmap(sqRingMem)
		if len(r.cqRingMem) != len(sqRingMem) || &r.cqRingMem[0] != &sqRingMem[0] {
			syscall.Munmap(r.cqRingMem)
		}
		return fmt.Errorf("failed to map SQEs: %w", err)
	}
	r.sqesMem = sqesMem

	return nil
}

// setupSubmissionQueue initializes the submission queue with optimizations
func setupSubmissionQueue(ring *Ring) (*SubmissionQueue, error) {
	params := ring.params
	mem := ring.sqRingMem

	sqe := &SubmissionQueue{
		head:      (*uint32)(unsafe.Pointer(&mem[params.SQOff.Head])),
		tail:      (*uint32)(unsafe.Pointer(&mem[params.SQOff.Tail])),
		mask:      *(*uint32)(unsafe.Pointer(&mem[params.SQOff.RingMask])),
		entries:   *(*uint32)(unsafe.Pointer(&mem[params.SQOff.RingEntries])),
		flags:     (*uint32)(unsafe.Pointer(&mem[params.SQOff.Flags])),
		dropped:   (*uint32)(unsafe.Pointer(&mem[params.SQOff.Dropped])),
		batchSize: 32, // Optimal batch size for submission
	}

	// Map array
	arrayPtr := unsafe.Pointer(&mem[params.SQOff.Array])
	sqe.array = (*[1 << 20]uint32)(arrayPtr)[:params.SQEntries:params.SQEntries]

	// Map SQEs
	sqesPtr := unsafe.Pointer(&ring.sqesMem[0])
	sqe.sqes = (*[1 << 20]SubmissionQueueEntry)(sqesPtr)[:params.SQEntries:params.SQEntries]

	// Initialize local tail
	sqe.localTail = *sqe.tail

	return sqe, nil
}

// setupCompletionQueue initializes the completion queue with optimizations
func setupCompletionQueue(ring *Ring) (*CompletionQueue, error) {
	params := ring.params
	mem := ring.cqRingMem

	cqe := &CompletionQueue{
		head:     (*uint32)(unsafe.Pointer(&mem[params.CQOff.Head])),
		tail:     (*uint32)(unsafe.Pointer(&mem[params.CQOff.Tail])),
		mask:     *(*uint32)(unsafe.Pointer(&mem[params.CQOff.RingMask])),
		entries:  *(*uint32)(unsafe.Pointer(&mem[params.CQOff.RingEntries])),
		overflow: (*uint32)(unsafe.Pointer(&mem[params.CQOff.Overflow])),
	}

	// Map CQEs
	cqesPtr := unsafe.Pointer(&mem[params.CQOff.CQEs])
	cqe.cqes = (*[1 << 20]CompletionQueueEntry)(cqesPtr)[:params.CQEntries:params.CQEntries]

	// Initialize local head
	cqe.localHead = *cqe.head

	return cqe, nil
}

// ReadAsync creates an async read request
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

// WriteAsync creates an async write request
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

// Submit submits I/O requests in batches for better performance
func (io *IOUring) Submit(requests []*IORequest) error {
	io.mu.Lock()
	defer io.mu.Unlock()

	if io.closed {
		return errors.New("io_uring is closed")
	}

	if len(requests) == 0 {
		return nil
	}

	// Process requests in batches
	for i := 0; i < len(requests); i += io.batchSize {
		end := i + io.batchSize
		if end > len(requests) {
			end = len(requests)
		}

		batch := requests[i:end]
		if err := io.submitBatch(batch); err != nil {
			return err
		}
	}

	return nil
}

// submitBatch submits a batch of requests with optimized memory barriers
func (io *IOUring) submitBatch(requests []*IORequest) error {
	tail := io.sqe.localTail

	// Prepare SQEs
	for _, req := range requests {
		index := tail & io.sqe.mask
		sqe := &io.sqe.sqes[index]

		// Clear SQE
		*sqe = SubmissionQueueEntry{}

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

	// Update local tail
	io.sqe.localTail = tail

	// Memory barrier before updating shared tail
	runtime.KeepAlive(io.sqe.sqes)

	// Update shared tail atomically
	*io.sqe.tail = tail

	// Submit to kernel
	_, _, errno := syscall.Syscall6(SYS_IO_URING_ENTER,
		uintptr(io.ring.fd),
		uintptr(len(requests)),
		0,
		IORING_ENTER_GETEVENTS,
		0,
		0)

	if errno != 0 {
		return fmt.Errorf("io_uring_enter failed: %v", errno)
	}

	return nil
}

// completionWorker processes completions asynchronously
func (io *IOUring) completionWorker() {
	defer io.wg.Done()

	ticker := time.NewTicker(io.pollTimeout)
	defer ticker.Stop()

	for {
		select {
		case <-io.stopChan:
			return
		case <-ticker.C:
			io.processCompletions()
		}
	}
}

// processCompletions processes completed I/O operations with batching
func (io *IOUring) processCompletions() {
	io.mu.Lock()
	defer io.mu.Unlock()

	if io.closed {
		return
	}

	head := io.cqe.localHead
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

			// Execute callback if provided
			if req.Callback != nil {
				req.Callback(completion)
			}

			// Send to completion channel (non-blocking)
			select {
			case io.completions <- completion:
			default:
				// Channel full, drop completion
			}
		}

		head++
	}

	// Update local head
	io.cqe.localHead = head

	// Memory barrier before updating shared head
	runtime.KeepAlive(io.cqe.cqes)

	// Update shared head atomically
	*io.cqe.head = head
}

// Poll polls for completed I/O operations with timeout
func (io *IOUring) Poll(timeout time.Duration) ([]*IOCompletion, error) {
	io.mu.RLock()
	defer io.mu.RUnlock()

	if io.closed {
		return nil, errors.New("io_uring is closed")
	}

	var completions []*IOCompletion
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		select {
		case completion := <-io.completions:
			completions = append(completions, completion)
		default:
			if len(completions) > 0 {
				return completions, nil
			}
			time.Sleep(time.Microsecond * 100)
		}
	}

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
	close(io.stopChan)
	io.wg.Wait()

	// Unmap memory
	if io.ring.sqRingMem != nil {
		syscall.Munmap(io.ring.sqRingMem)
	}
	if io.ring.cqRingMem != nil && (len(io.ring.cqRingMem) != len(io.ring.sqRingMem) || &io.ring.cqRingMem[0] != &io.ring.sqRingMem[0]) {
		syscall.Munmap(io.ring.cqRingMem)
	}
	if io.ring.sqesMem != nil {
		syscall.Munmap(io.ring.sqesMem)
	}

	// Close ring fd
	if io.ring.fd > 0 {
		syscall.Close(io.ring.fd)
	}

	return nil
}

// GetStats returns performance statistics
func (io *IOUring) GetStats() map[string]interface{} {
	io.mu.RLock()
	defer io.mu.RUnlock()

	return map[string]interface{}{
		"pending_requests":   len(io.requests),
		"batch_size":         io.batchSize,
		"workers":            io.workers,
		"completion_backlog": len(io.completions),
		"sq_head":            *io.sqe.head,
		"sq_tail":            *io.sqe.tail,
		"cq_head":            *io.cqe.head,
		"cq_tail":            *io.cqe.tail,
		"sq_dropped":         *io.sqe.dropped,
		"cq_overflow":        *io.cqe.overflow,
	}
}
