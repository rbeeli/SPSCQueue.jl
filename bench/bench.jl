using ThreadPinning
using SPSCQueue

include("../test/shm.jl");
include("../src/rdtsc.jl");

function commas(num::Integer)
    replace(string(num), r"(?<=[0-9])(?=(?:[0-9]{3})+(?![0-9]))" => "'")
end

function producer(queue::SPSCQueueVar)
    println("producer started")

    # 8 bytes message (rdtsc clock value)
    size = 8
    data = UInt64[rdtsc()]
    data_ptr = pointer(data)
    msg = SPSCMessage(data_ptr, size)
    i = 0
    while true
        unsafe_store!(data_ptr, rdtsc())

        while !enqueue!(queue, msg)
        end

        i += 1
    end

    println("producer done")
end

function consumer(queue::SPSCQueueVar)
    println("consumer started")

    log_interval = 5_000_000
    last_clock = rdtsc()
    cycles_per_ns::Float64 = 3.2 # ~3.2 cycles per ns (measured on machine)
    counter::Int = 0
    avg_latency::UInt64 = 0.0
    while true
    # while counter != 10^9
        msg_view = dequeue!(queue)
        if !isempty(msg_view)
            clock::UInt64 = rdtsc()
            # clock = time_ns()
            remote_rdtsc::UInt64 = unsafe_load(reinterpret(Ptr{UInt64}, msg_view.data))
            dequeue_commit!(queue, msg_view)
            counter += 1
            latency::UInt64 = clock - remote_rdtsc
            avg_latency += latency
            if counter % log_interval == 0
                latency_ns = floor(Int, latency / cycles_per_ns)
                avg_latency_ns = floor(Int, avg_latency / log_interval / cycles_per_ns)

                delta_clock = clock - last_clock
                msgs_s = floor(UInt64, log_interval / (delta_clock / 1e9 / cycles_per_ns))
                println("consumed $counter   $(commas(msgs_s)) msgs/s  latency: $latency_ns ns  avg. latency = $avg_latency_ns ns  (tid=$(Base.Threads.threadid()))")

                last_clock = clock
                avg_latency = 0.0
            end
        end
    end

    println("consumer done")
end


function run()
    # --------------------
    # in-memory

    # buffer_size = 100_000 # bytes
    # storage = SPSCStorage(buffer_size)

    # --------------------
    # shared memory buffer only

    shm_fd, shm_size, buffer_ptr = shm_open(
        "pubsub_test_1"
        # "bybit_orderbook_linear_julia_test"
        # "bybit_trades_linear_julia_test"
        ;
        # shm_flags = Base.Filesystem.JL_O_CREAT |
        #     Base.Filesystem.JL_O_RDWR |
        #     Base.Filesystem.JL_O_TRUNC,
        shm_flags=Base.Filesystem.JL_O_RDWR,
        shm_mode=0o666
    )
    # storage = SPSCStorage(buffer_ptr, shm_size)
    storage = SPSCStorage(buffer_ptr)

    println("storage_size:       $(storage.storage_size)")
    println("buffer_size:        $(storage.buffer_size)")
    println("read_ix:            $(unsafe_load(storage.read_ix, :acquire))")
    println("write_ix:           $(unsafe_load(storage.write_ix, :acquire))")

    # create variable-element size SPSC queue
    queue = SPSCQueueVar(storage)

    # p_thread = @tspawnat 3 producer(queue) # 1-based indexing
    # c_thread = @tspawnat 5 consumer(queue) # 1-based indexing

    setaffinity([4]) # 0-based
    consumer(queue)
    # setaffinity([2]) # 0-based
    # producer(queue)

    # wait(p_thread)
    # wait(c_thread)
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
