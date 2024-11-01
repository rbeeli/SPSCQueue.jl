occursin("bench", pwd()) || cd("bench");

using ThreadPinning
using SPSCQueue
using SPSCQueue.SharedMemory

commas(num::Integer) = replace(string(num), r"(?<=[0-9])(?=(?:[0-9]{3})+(?![0-9]))" => "'")

function producer(queue::SPSCQueueVar)
    println("producer started")

    # 8 bytes message (counter
    size = 8
    data = UInt64[0]
    data_ptr = pointer(data)
    msg = SPSCMessage(data_ptr, size)
    i = 0
    while true
        i += 1

        unsafe_store!(data_ptr, i)

        while !enqueue!(queue, msg)
        end
    end

    println("producer done")
end

function consumer(queue::SPSCQueueVar)
    println("consumer started")

    log_interval = 10_000_000
    next_log = log_interval
    last_clock = time_ns()
    while true
        msg_view = dequeue_begin!(queue)
        if !isempty(msg_view)
            counter = unsafe_load(reinterpret(Ptr{UInt64}, msg_view.data))
            dequeue_commit!(queue, msg_view)

            if counter == next_log
                clock = time_ns()
                delta_clock = clock - last_clock
                msgs_s = floor(UInt64, log_interval / (delta_clock / 1e9))
                println("consumed $counter   $(commas(msgs_s)) msgs/s  (tid=$(Base.Threads.threadid()))")

                last_clock = clock
                next_log += log_interval
            end
        end
    end

    println("consumer done")
end


function run()
    buffer_size = 100_000 # bytes

    # --------------------
    # in-memory
    # storage = SPSCStorage(buffer_size)

    # --------------------
    # shared memory buffer only
    shm_fd, shm_size, buffer_ptr = shm_open(
        "pubsub_test_1"
        # "bybit_orderbook_linear_julia_test"
        # "bybit_trades_linear_julia_test"
        ;
        shm_flags = Base.Filesystem.JL_O_CREAT |
            Base.Filesystem.JL_O_RDWR |
            Base.Filesystem.JL_O_TRUNC,
        # shm_flags=Base.Filesystem.JL_O_RDWR,
        shm_mode=0o666,
        size=buffer_size
    )
    storage = SPSCStorage(buffer_ptr, shm_size)
    # storage = SPSCStorage(buffer_ptr) # use if opening existing initialized shared memory

    println("storage_size:       $(storage.storage_size)")
    println("buffer_size:        $(storage.buffer_size)")
    println("read_ix:            $(unsafe_load(storage.read_ix, :acquire))")
    println("write_ix:           $(unsafe_load(storage.write_ix, :acquire))")

    # create variable-element size SPSC queue
    queue = SPSCQueueVar(storage)

    p_thread = @tspawnat 3 producer(queue) # 1-based indexing
    c_thread = @tspawnat 5 consumer(queue) # 1-based indexing

    # setaffinity([4]) # 0-based
    # consumer(queue)
    # setaffinity([2]) # 0-based
    # producer(queue)

    wait(p_thread)
    wait(c_thread)
end

GC.enable(false)
GC.enable_logging(true)

println("n threads: $(Base.Threads.nthreads())")

run()

# julia --project=. --threads=24 bench/bench.jl

# using ProfileView
# ProfileView.@profview run()
# VSCodeServer.@profview run()

# using InteractiveUtils
# display(@code_warntype run())
