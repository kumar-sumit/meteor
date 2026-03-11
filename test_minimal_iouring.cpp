// **MINIMAL WORKING io_uring SERVER FOR DEBUGGING**
#include <iostream>
#include <liburing.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

#define QUEUE_DEPTH 32
#define BUFFER_SIZE 1024

struct io_data {
    int type; // 0=accept, 1=read, 2=write
    int fd;
    char buffer[BUFFER_SIZE];
    int len;
};

int main() {
    struct io_uring ring;
    io_uring_queue_init(QUEUE_DEPTH, &ring, 0);
    
    // Create socket
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(6390);
    
    bind(server_fd, (struct sockaddr*)&addr, sizeof(addr));
    listen(server_fd, 128);
    
    std::cout << "✅ Minimal io_uring server listening on port 6390" << std::endl;
    
    // Submit initial accept
    struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
    io_data *data = new io_data{0, server_fd, {}, 0};
    io_uring_prep_accept(sqe, server_fd, nullptr, nullptr, 0);
    io_uring_sqe_set_data(sqe, data);
    io_uring_submit(&ring);
    
    while (true) {
        struct io_uring_cqe *cqe;
        io_uring_wait_cqe(&ring, &cqe);
        
        io_data *data = (io_data*)io_uring_cqe_get_data(cqe);
        int result = cqe->res;
        
        if (data->type == 0) { // accept
            if (result > 0) {
                int client_fd = result;
                std::cout << "✅ Accepted client fd=" << client_fd << std::endl;
                
                // Submit read for this client
                sqe = io_uring_get_sqe(&ring);
                io_data *read_data = new io_data{1, client_fd, {}, 0};
                io_uring_prep_recv(sqe, client_fd, read_data->buffer, BUFFER_SIZE, 0);
                io_uring_sqe_set_data(sqe, read_data);
                io_uring_submit(&ring);
                
                // Submit next accept
                sqe = io_uring_get_sqe(&ring);
                io_data *accept_data = new io_data{0, server_fd, {}, 0};
                io_uring_prep_accept(sqe, server_fd, nullptr, nullptr, 0);
                io_uring_sqe_set_data(sqe, accept_data);
                io_uring_submit(&ring);
            }
        } else if (data->type == 1) { // read
            if (result > 0) {
                std::cout << "📥 Read " << result << " bytes from fd=" << data->fd << std::endl;
                
                // Send PONG response
                const char* response = "+PONG\\r\\n";
                sqe = io_uring_get_sqe(&ring);
                io_data *write_data = new io_data{2, data->fd, {}, 7};
                strcpy(write_data->buffer, response);
                io_uring_prep_send(sqe, data->fd, write_data->buffer, 7, 0);
                io_uring_sqe_set_data(sqe, write_data);
                io_uring_submit(&ring);
                
                // Submit next read for same client
                sqe = io_uring_get_sqe(&ring);
                io_data *next_read = new io_data{1, data->fd, {}, 0};
                io_uring_prep_recv(sqe, data->fd, next_read->buffer, BUFFER_SIZE, 0);
                io_uring_sqe_set_data(sqe, next_read);
                io_uring_submit(&ring);
            } else {
                std::cout << "🔌 Client fd=" << data->fd << " disconnected" << std::endl;
                close(data->fd);
            }
        } else if (data->type == 2) { // write
            if (result > 0) {
                std::cout << "📤 Wrote " << result << " bytes to fd=" << data->fd << std::endl;
            }
        }
        
        delete data;
        io_uring_cqe_seen(&ring, cqe);
    }
    
    return 0;
}