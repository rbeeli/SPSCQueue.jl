# SPSCQueue.jl

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A fast single-producer, single-consumer queue implementation in pure Julia.

The SPSC queue allows to push variable-sized binary messages into a queue from one thread, and pop them from another thread.
The queue is lock-free and uses a circular buffer to store the messages.

The queue memory can be used directly by the consumer as long as the dequeue-operation hasn't been performed (`dequeue_commit!`), which allows for zero-copy message passing.

On a 12th Gen Intel(R) Core(TM) i9-12900K running Ubuntu 22.04 x64, the queue can:

* push and pop over 180 million 8-byte messages per second
* achieve latencies of < 100 nanoseconds in the non-contended case

The queue storage can be allocated on the heap, or in shared memory.

## API

The queue is implemented in the `SPSCQueue` module, and provides the following functions:

```julia
# create storage memory for queue on heap
SPSCStorage(storage_size::Integer)

# create new storage for queue from an UInt8 pointer
SPSCStorage(ptr::Ptr{T}, storage_size::Integer; finalizer_fn::Function)

# open existing storage for queue from an UInt8 pointer
SPSCStorage(ptr::Ptr{T}; finalizer_fn::Function)

# create a variable-element size SPSC queue
SPSCQueueVar(storage::SPSCStorage)

# push a message onto the queue
enqueue(queue::SPSCQueueVar, msg::SPSCMessage) 

# pop a message from the queue
dequeue(queue::SPSCQueueVar)

# commit the message after it has been processed by the consumer
dequeue_commit!(queue::SPSCQueueVar, msg_view::SPSCMessageView)

# check if the popped message view is empty, i.e. if dequeue returned a message
isempty(msg_view::SPSCMessageView)
```

## Example

The following example creates a SPSC queue with a fixed-size ring buffer of 100,000 bytes.
The queue itself allows to push and pop variable-sized messages. We send 1,000,000 messages from the producer to the consumer, and print the status every 10,000 messages.

### Basic usage

```julia
using ThreadPinning
using SPSCQueue

function producer(queue::SPSCQueueVar, iterations::Int64)
    println("producer started")

    # 8 bytes message
    size = 8
    data = Int64[0]
    data_ptr = pointer(data)
    msg = SPSCMessage(data_ptr, size)
    for counter in 1:iterations
        # store counter value in message
        unsafe_store!(data_ptr, counter)

        # enqueue message
        while !enqueue(queue, msg)
            # queue full - busy wait
        end

        # print status
        if counter % 10_000 == 0
            println("> sent $counter")
        end
    end

    println("producer done")
end

function consumer(queue::SPSCQueueVar, iterations::Int64)
    println("consumer started")

    counter = 0
    while counter < iterations
        msg_view = dequeue(queue)
        if !isempty(msg_view)
            # get counter value from message
            counter = unsafe_load(reinterpret(Ptr{Int64}, msg_view.data))

            # commit message
            dequeue_commit!(queue, msg_view)

            # print status
            if counter % 10_000 == 0
                println("< received $counter")
            end
        end
    end

    println("consumer done")
end

function run()
    buffer_size = 100_000 # bytes
    storage = SPSCStorage(buffer_size)

    # create variable-element size SPSC queue
    queue = SPSCQueueVar(storage)

    # spawn producer and consumer threads, pin them to cores 3 and 5
    iterations = 1_000_000
    p_thread = @tspawnat 3 producer(queue, iterations) # 1-based indexing
    c_thread = @tspawnat 5 consumer(queue, iterations) # 1-based indexing

    wait(p_thread)
    wait(c_thread)
end

run()
```

See [examples/basic.jl](examples/basic.jl) for the example file.

### Shared memory

The queue storage can be allocated in shared memory, which allows to use the queue for inter-process communication.
Instead of using `SPSCStorage(buffer_size)`, use `SPSCStorage(ptr, storage_size; finalizer_fn)` to create the storage from a pointer to shared memory.

`SPSCStorage` can work with arbitrary `Ptr{T}` types. It is the user's responsibility to manage the shared memory and provide the correct pointer and size. Optionally, a finalizer function can be provided to clean up the shared memory when the storage is no longer needed.

Example of creating a shared memory queue (Linux only in this example):

```julia
buffer_size = 100_000 # bytes
shm_size = buffer_size + SPSC_STORAGE_BUFFER_OFFSET

# works only on Linux (see src/shm.jl for details)
shm_fd, shm_size, shm_ptr = shm_open(
    "my_shared_memory",
    shm_flags = Base.Filesystem.JL_O_CREAT |
        Base.Filesystem.JL_O_RDWR |
        Base.Filesystem.JL_O_TRUNC,
    shm_mode=0o666,
    size=shm_size
)
storage = SPSCStorage(shm_ptr, shm_size)
```

See [examples/shared_memory.jl](examples/shared_memory.jl) for the example file.
