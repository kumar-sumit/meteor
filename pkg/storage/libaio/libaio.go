package libaio

import (
	"errors"
	"runtime"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

// Syscall numbers for libaio (x86_64)
const (
	SYS_IO_SETUP     = 206
	SYS_IO_DESTROY   = 207
	SYS_IO_GETEVENTS = 208
	SYS_IO_SUBMIT    = 209
)

// LibAIO represents a libaio context
type LibAIO struct {
	ctx       uintptr
	maxEvents int
	mu        sync.Mutex
	closed    bool
	requests  map[uint64]*IORequest
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

// iocb represents the I/O control block
type iocb struct {
	aio_data       uint64
	aio_key        uint32
	aio_rw_flags   uint32
	aio_lio_opcode uint16
	aio_reqprio    int16
	aio_fildes     uint32
	aio_buf        uint64
	aio_nbytes     uint64
	aio_offset     int64
	aio_reserved2  uint64
	aio_flags      uint32
	aio_resfd      uint32
}

// io_event represents an I/O event
type io_event struct {
	data uint64
	obj  uint64
	res  int64
	res2 int64
}

// NewLibAIO creates a new libaio context
func NewLibAIO(maxEvents int) (*LibAIO, error) {
	// Check if libaio is available
	if !isLibAIOAvailable() {
		return nil, errors.New("libaio not available on this system")
	}

	ctx, err := io_setup(maxEvents)
	if err != nil {
		return nil, err
	}

	return &LibAIO{
		ctx:       ctx,
		maxEvents: maxEvents,
		requests:  make(map[uint64]*IORequest),
	}, nil
}

// isLibAIOAvailable checks if libaio is available
func isLibAIOAvailable() bool {
	// libaio is Linux-specific
	if runtime.GOOS != "linux" {
		return false
	}

	// Try to create a minimal context to test availability
	ctx, err := io_setup(1)
	if err != nil {
		return false
	}
	io_destroy(ctx)
	return true
}

// io_setup initializes an AIO context
func io_setup(maxEvents int) (uintptr, error) {
	var ctx uintptr
	r1, _, errno := syscall.Syscall(SYS_IO_SETUP,
		uintptr(maxEvents),
		uintptr(unsafe.Pointer(&ctx)),
		0)
	if errno != 0 {
		return 0, errno
	}
	if r1 != 0 {
		return 0, syscall.Errno(r1)
	}
	return ctx, nil
}

// io_destroy destroys an AIO context
func io_destroy(ctx uintptr) error {
	r1, _, errno := syscall.Syscall(SYS_IO_DESTROY, ctx, 0, 0)
	if errno != 0 {
		return errno
	}
	if r1 != 0 {
		return syscall.Errno(r1)
	}
	return nil
}

// io_submit submits I/O requests
func io_submit(ctx uintptr, nr int, iocbpp uintptr) (int, error) {
	r1, _, errno := syscall.Syscall(SYS_IO_SUBMIT, ctx, uintptr(nr), iocbpp)
	if errno != 0 {
		return 0, errno
	}
	return int(r1), nil
}

// io_getevents retrieves completed I/O events
func io_getevents(ctx uintptr, minNr, nr int, events uintptr, timeout uintptr) (int, error) {
	r1, _, errno := syscall.Syscall6(SYS_IO_GETEVENTS,
		ctx,
		uintptr(minNr),
		uintptr(nr),
		events,
		timeout,
		0)
	if errno != 0 {
		return 0, errno
	}
	return int(r1), nil
}

// ReadAsync submits an asynchronous read request
func (aio *LibAIO) ReadAsync(fd int, offset int64, buf []byte) (*IORequest, error) {
	aio.mu.Lock()
	defer aio.mu.Unlock()

	if aio.closed {
		return nil, errors.New("libaio context is closed")
	}

	req := &IORequest{
		ID:     uint64(len(aio.requests)) + 1,
		Type:   IOTypeRead,
		FD:     fd,
		Offset: offset,
		Buffer: buf,
	}

	aio.requests[req.ID] = req
	return req, nil
}

// WriteAsync submits an asynchronous write request
func (aio *LibAIO) WriteAsync(fd int, offset int64, buf []byte) (*IORequest, error) {
	aio.mu.Lock()
	defer aio.mu.Unlock()

	if aio.closed {
		return nil, errors.New("libaio context is closed")
	}

	req := &IORequest{
		ID:     uint64(len(aio.requests)) + 1,
		Type:   IOTypeWrite,
		FD:     fd,
		Offset: offset,
		Buffer: buf,
	}

	aio.requests[req.ID] = req
	return req, nil
}

// Submit submits I/O requests to the kernel
func (aio *LibAIO) Submit(requests []*IORequest) error {
	aio.mu.Lock()
	defer aio.mu.Unlock()

	if aio.closed {
		return errors.New("libaio context is closed")
	}

	if len(requests) == 0 {
		return nil
	}

	// Create iocb array
	iocbs := make([]iocb, len(requests))
	iocbPtrs := make([]*iocb, len(requests))

	for i, req := range requests {
		iocb := &iocbs[i]
		iocb.aio_data = req.ID
		iocb.aio_fildes = uint32(req.FD)
		iocb.aio_buf = uint64(uintptr(unsafe.Pointer(&req.Buffer[0])))
		iocb.aio_nbytes = uint64(len(req.Buffer))
		iocb.aio_offset = req.Offset

		if req.Type == IOTypeRead {
			iocb.aio_lio_opcode = 0 // IOCB_CMD_PREAD
		} else {
			iocb.aio_lio_opcode = 1 // IOCB_CMD_PWRITE
		}

		iocbPtrs[i] = iocb
	}

	// Submit to kernel
	submitted, err := io_submit(aio.ctx, len(iocbPtrs), uintptr(unsafe.Pointer(&iocbPtrs[0])))
	if err != nil {
		return err
	}

	if submitted != len(requests) {
		return errors.New("failed to submit all requests")
	}

	return nil
}

// Poll polls for completed I/O operations
func (aio *LibAIO) Poll(timeout time.Duration) ([]*IOCompletion, error) {
	aio.mu.Lock()
	defer aio.mu.Unlock()

	if aio.closed {
		return nil, errors.New("libaio context is closed")
	}

	events := make([]io_event, aio.maxEvents)
	var timeoutSpec *syscall.Timespec

	if timeout > 0 {
		timeoutSpec = &syscall.Timespec{
			Sec:  int64(timeout / time.Second),
			Nsec: int64(timeout % time.Second),
		}
	}

	var timeoutPtr uintptr
	if timeoutSpec != nil {
		timeoutPtr = uintptr(unsafe.Pointer(timeoutSpec))
	}

	n, err := io_getevents(aio.ctx, 0, aio.maxEvents,
		uintptr(unsafe.Pointer(&events[0])), timeoutPtr)
	if err != nil {
		return nil, err
	}

	completions := make([]*IOCompletion, 0, n)
	for i := 0; i < n; i++ {
		event := &events[i]
		reqID := event.data

		req, exists := aio.requests[reqID]
		if !exists {
			continue
		}

		delete(aio.requests, reqID)

		completion := &IOCompletion{
			Request: req,
			Result:  int(event.res),
		}

		if event.res < 0 {
			completion.Error = syscall.Errno(-event.res)
		}

		completions = append(completions, completion)
	}

	return completions, nil
}

// Close closes the libaio context
func (aio *LibAIO) Close() error {
	aio.mu.Lock()
	defer aio.mu.Unlock()

	if aio.closed {
		return nil
	}

	aio.closed = true
	return io_destroy(aio.ctx)
}
