occursin("bench", pwd()) || cd("bench");

using ThreadPinning
using PosixIPC.Queues
using PosixIPC.Queues.SPSC
using PosixIPC.SharedMemory

include("../src/rdtsc.jl");

commas(num::Integer) = replace(string(num), r"(?<=[0-9])(?=(?:[0-9]{3})+(?![0-9]))" => "'")

function producer(queue::SPSCQueueVar)
    println("producer started")

    # 8 bytes message (RDTSC clock value)
    size = 8
    data = UInt64[0]
    data_ptr = pointer(data)
    msg = Message(data_ptr, size)
    i = 0
    while true
        i += 1

        unsafe_store!(data_ptr, rdtsc())

        while !enqueue!(queue, msg)
        end
        
        yield() # make producer slower than consumer
    end

    println("producer done")
end

function consumer(queue::SPSCQueueVar)
    println("consumer started")

    cycles_per_ns = measure_rdtsc_cycles_per_ns()
    println("RDTSC cycles per ns: $cycles_per_ns")

    log_interval = 1_000_000
    last_clock = rdtsc()
    counter::Int = 0
    latency_sum::UInt64 = 0
    while true
        msg_view = dequeue_begin!(queue)
        if !isempty(msg_view)
            clock = rdtsc()
            counter += 1
            remote_rdtsc::UInt64 = unsafe_load(reinterpret(Ptr{UInt64}, msg_view.data))
            latency_sum += clock - remote_rdtsc
            
            if counter == log_interval
                avg_latency_ns = floor(Int, latency_sum / cycles_per_ns / log_interval)

                delta_clock = clock - last_clock
                msgs_s = floor(UInt64, log_interval / (delta_clock / 1e9 / cycles_per_ns))
                println("consumed $counter   $(commas(msgs_s)) msgs/s  avg. latency = $avg_latency_ns ns  (tid=$(Base.Threads.threadid()))")

                last_clock = clock
                latency_sum = 0
                counter = 0
            end

            dequeue_commit!(queue, msg_view)
        end
    end

    println("consumer done")
end


function run()
    buffer_size = 100_000 # bytes

    # --------------------
    # in-memory
    storage = SPSCStorage(buffer_size)

    # --------------------
    # shared memory buffer only
    # shm = shm_open(
    #     "pubsub_test_1",
    #     # "bybit_orderbook_linear_julia_test",
    #     # "bybit_trades_linear_julia_test",
    #     # oflag = Base.Filesystem.JL_O_CREAT |
    #     #     Base.Filesystem.JL_O_RDWR |
    #     #     Base.Filesystem.JL_O_TRUNC,
    #     oflag=Base.Filesystem.JL_O_RDWR,
    #     mode=0o666,
    #     size=buffer_size
    # )
    # storage = SPSCStorage(shm.ptr, shm.size)
    # # storage = SPSCStorage(shm.ptr) # use if opening existing initialized shared memory

    println("storage_size:       $(storage.storage_size)")
    println("buffer_size:        $(storage.buffer_size)")
    println("read_ix:            $(unsafe_load(storage.read_ix, :acquire))")
    println("write_ix:           $(unsafe_load(storage.write_ix, :acquire))")

    # create variable-element size SPSC queue
    queue = SPSCQueueVar(storage)

    # spawn producer thread on core 3
    p_thread = ThreadPinning.@spawnat 3 producer(queue) # 1-based indexing

    # run consumer on main thread (core 5)
    pinthread(4) # 0-based indexing
    consumer(queue)

    wait(p_thread)
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
