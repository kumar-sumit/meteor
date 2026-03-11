package storage

import (
	"time"

	"github.com/kumar-sumit/meteor/pkg/storage/iouring"
	"github.com/kumar-sumit/meteor/pkg/storage/libaio"
)

// IOUringAdapter adapts iouring.IOUring to the IOBackend interface
type IOUringAdapter struct {
	ring *iouring.IOUring
}

func NewIOUringAdapter(entries uint32) (*IOUringAdapter, error) {
	ring, err := iouring.NewIOUring(entries)
	if err != nil {
		return nil, err
	}
	return &IOUringAdapter{ring: ring}, nil
}

func (a *IOUringAdapter) ReadAsync(fd int, offset int64, buf []byte) (*IORequest, error) {
	req, err := a.ring.ReadAsync(fd, offset, buf)
	if err != nil {
		return nil, err
	}

	// Convert iouring.IORequest to storage.IORequest
	return &IORequest{
		ID:       req.ID,
		Type:     IOType(req.Type),
		FD:       req.FD,
		Offset:   req.Offset,
		Buffer:   req.Buffer,
		Callback: convertIOUringCallback(req.Callback),
		UserData: req.UserData,
	}, nil
}

func (a *IOUringAdapter) WriteAsync(fd int, offset int64, buf []byte) (*IORequest, error) {
	req, err := a.ring.WriteAsync(fd, offset, buf)
	if err != nil {
		return nil, err
	}

	// Convert iouring.IORequest to storage.IORequest
	return &IORequest{
		ID:       req.ID,
		Type:     IOType(req.Type),
		FD:       req.FD,
		Offset:   req.Offset,
		Buffer:   req.Buffer,
		Callback: convertIOUringCallback(req.Callback),
		UserData: req.UserData,
	}, nil
}

func (a *IOUringAdapter) Submit(requests []*IORequest) error {
	// Convert storage.IORequest to iouring.IORequest
	iouringReqs := make([]*iouring.IORequest, len(requests))
	for i, req := range requests {
		iouringReqs[i] = &iouring.IORequest{
			ID:       req.ID,
			Type:     iouring.IOType(req.Type),
			FD:       req.FD,
			Offset:   req.Offset,
			Buffer:   req.Buffer,
			Callback: convertStorageCallback(req.Callback),
			UserData: req.UserData,
		}
	}

	return a.ring.Submit(iouringReqs)
}

func (a *IOUringAdapter) Poll(timeout time.Duration) ([]*IOCompletion, error) {
	completions, err := a.ring.Poll(timeout)
	if err != nil {
		return nil, err
	}

	// Convert iouring.IOCompletion to storage.IOCompletion
	result := make([]*IOCompletion, len(completions))
	for i, comp := range completions {
		result[i] = &IOCompletion{
			Request: &IORequest{
				ID:       comp.Request.ID,
				Type:     IOType(comp.Request.Type),
				FD:       comp.Request.FD,
				Offset:   comp.Request.Offset,
				Buffer:   comp.Request.Buffer,
				UserData: comp.Request.UserData,
			},
			Result: comp.Result,
			Error:  comp.Error,
		}
	}

	return result, nil
}

func (a *IOUringAdapter) Close() error {
	return a.ring.Close()
}

// LibAIOAdapter adapts libaio.LibAIO to the IOBackend interface
type LibAIOAdapter struct {
	aio *libaio.LibAIO
}

func NewLibAIOAdapter(maxEvents int) (*LibAIOAdapter, error) {
	aio, err := libaio.NewLibAIO(maxEvents)
	if err != nil {
		return nil, err
	}
	return &LibAIOAdapter{aio: aio}, nil
}

func (a *LibAIOAdapter) ReadAsync(fd int, offset int64, buf []byte) (*IORequest, error) {
	req, err := a.aio.ReadAsync(fd, offset, buf)
	if err != nil {
		return nil, err
	}

	// Convert libaio.IORequest to storage.IORequest
	return &IORequest{
		ID:       req.ID,
		Type:     IOType(req.Type),
		FD:       req.FD,
		Offset:   req.Offset,
		Buffer:   req.Buffer,
		Callback: convertLibAIOCallback(req.Callback),
		UserData: req.UserData,
	}, nil
}

func (a *LibAIOAdapter) WriteAsync(fd int, offset int64, buf []byte) (*IORequest, error) {
	req, err := a.aio.WriteAsync(fd, offset, buf)
	if err != nil {
		return nil, err
	}

	// Convert libaio.IORequest to storage.IORequest
	return &IORequest{
		ID:       req.ID,
		Type:     IOType(req.Type),
		FD:       req.FD,
		Offset:   req.Offset,
		Buffer:   req.Buffer,
		Callback: convertLibAIOCallback(req.Callback),
		UserData: req.UserData,
	}, nil
}

func (a *LibAIOAdapter) Submit(requests []*IORequest) error {
	// Convert storage.IORequest to libaio.IORequest
	libaioReqs := make([]*libaio.IORequest, len(requests))
	for i, req := range requests {
		libaioReqs[i] = &libaio.IORequest{
			ID:       req.ID,
			Type:     libaio.IOType(req.Type),
			FD:       req.FD,
			Offset:   req.Offset,
			Buffer:   req.Buffer,
			Callback: convertStorageCallbackLibAIO(req.Callback),
			UserData: req.UserData,
		}
	}

	return a.aio.Submit(libaioReqs)
}

func (a *LibAIOAdapter) Poll(timeout time.Duration) ([]*IOCompletion, error) {
	completions, err := a.aio.Poll(timeout)
	if err != nil {
		return nil, err
	}

	// Convert libaio.IOCompletion to storage.IOCompletion
	result := make([]*IOCompletion, len(completions))
	for i, comp := range completions {
		result[i] = &IOCompletion{
			Request: &IORequest{
				ID:       comp.Request.ID,
				Type:     IOType(comp.Request.Type),
				FD:       comp.Request.FD,
				Offset:   comp.Request.Offset,
				Buffer:   comp.Request.Buffer,
				UserData: comp.Request.UserData,
			},
			Result: comp.Result,
			Error:  comp.Error,
		}
	}

	return result, nil
}

func (a *LibAIOAdapter) Close() error {
	return a.aio.Close()
}

// Helper functions to convert callbacks
func convertIOUringCallback(callback func(*iouring.IOCompletion)) func(*IOCompletion) {
	if callback == nil {
		return nil
	}
	return func(comp *IOCompletion) {
		iouringComp := &iouring.IOCompletion{
			Request: &iouring.IORequest{
				ID:       comp.Request.ID,
				Type:     iouring.IOType(comp.Request.Type),
				FD:       comp.Request.FD,
				Offset:   comp.Request.Offset,
				Buffer:   comp.Request.Buffer,
				UserData: comp.Request.UserData,
			},
			Result: comp.Result,
			Error:  comp.Error,
		}
		callback(iouringComp)
	}
}

func convertStorageCallback(callback func(*IOCompletion)) func(*iouring.IOCompletion) {
	if callback == nil {
		return nil
	}
	return func(comp *iouring.IOCompletion) {
		storageComp := &IOCompletion{
			Request: &IORequest{
				ID:       comp.Request.ID,
				Type:     IOType(comp.Request.Type),
				FD:       comp.Request.FD,
				Offset:   comp.Request.Offset,
				Buffer:   comp.Request.Buffer,
				UserData: comp.Request.UserData,
			},
			Result: comp.Result,
			Error:  comp.Error,
		}
		callback(storageComp)
	}
}

func convertLibAIOCallback(callback func(*libaio.IOCompletion)) func(*IOCompletion) {
	if callback == nil {
		return nil
	}
	return func(comp *IOCompletion) {
		libaioComp := &libaio.IOCompletion{
			Request: &libaio.IORequest{
				ID:       comp.Request.ID,
				Type:     libaio.IOType(comp.Request.Type),
				FD:       comp.Request.FD,
				Offset:   comp.Request.Offset,
				Buffer:   comp.Request.Buffer,
				UserData: comp.Request.UserData,
			},
			Result: comp.Result,
			Error:  comp.Error,
		}
		callback(libaioComp)
	}
}

func convertStorageCallbackLibAIO(callback func(*IOCompletion)) func(*libaio.IOCompletion) {
	if callback == nil {
		return nil
	}
	return func(comp *libaio.IOCompletion) {
		storageComp := &IOCompletion{
			Request: &IORequest{
				ID:       comp.Request.ID,
				Type:     IOType(comp.Request.Type),
				FD:       comp.Request.FD,
				Offset:   comp.Request.Offset,
				Buffer:   comp.Request.Buffer,
				UserData: comp.Request.UserData,
			},
			Result: comp.Result,
			Error:  comp.Error,
		}
		callback(storageComp)
	}
}
