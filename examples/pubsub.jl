using ThreadPinning
using PosixIPC.SharedMemory
using PosixIPC.Queues
using PosixIPC.Queues.PubSub

function producer(pub::PubSubHub, iterations::Int64)
    println("producer started")
    flush(stdout)

    # 8 bytes message
    size = 8
    data = Int64[0]
    GC.@preserve data begin
        data_ptr = pointer(data)
        msg = Message(data_ptr, size)
        for counter in 1:iterations
            # store counter value in message
            unsafe_store!(data_ptr, counter)

            # enqueue message
            while !publish!(pub, msg)
                # queue full - busy wait
            end

            # print status
            println("> sent $counter")
            flush(stdout)

            Base.Libc.systemsleep(0.01) # sleep for 10ms
        end
    end

    println("! producer done")
    flush(stdout)
end

function consumer(sub::Subscriber, iterations::Int64)
    println("consumer started")
    flush(stdout)

    counter = 0
    while counter < iterations
        msg_view = dequeue_begin!(sub)
        if !isempty(msg_view)
            # get counter value from message
            counter = unsafe_load(reinterpret(Ptr{Int64}, msg_view.data))

            # commit message
            dequeue_commit!(sub, msg_view)

            # print status
            println("< subscriber $(sub.config.shm_name) received $counter")
            flush(stdout)
        end
    end

    println("! consumer $(sub.config.shm_name) done")
    flush(stdout)
end

function run()
    config1 = PubSubConfig(
        "ex_pubsub_1",
        1_000_000,
        queue_full_policy=QueueFullPolicy.DROP_NEWEST,
        log_message_drop=true)

    config2 = PubSubConfig(
        "ex_pubsub_2",
        1_000_000,
        queue_full_policy=QueueFullPolicy.DROP_NEWEST,
        log_message_drop=true)
    
    pub_sub = PubSubHub()
    sync_configs!(pub_sub, [config1, config2])

    # spawn consumer threads, pin them to cores 3 and 5
    iterations = 100
    c1_thread = ThreadPinning.@spawnat 3 consumer(Subscriber(config1), iterations) # 1-based indexing
    c2_thread = ThreadPinning.@spawnat 5 consumer(Subscriber(config2), iterations) # 1-based indexing

    # run consumer on main thread (core 7)
    pinthread(6) # 0-based indexing
    producer(pub_sub, iterations)
    println("producer thread done")
    flush(stdout)

    try
        wait(c1_thread)
        println("c1 thread done")
        flush(stdout)
    catch e
        println("c1 thread error: $e")
    end

    try
        wait(c2_thread)
        println("c2 thread done")
        flush(stdout)
    catch e
        println("c2 thread error: $e")
    end

    # destroy shared memory object (deletes it from the system)
    shm_unlink(pub_sub.publishers[1].shm)
    shm_unlink(pub_sub.publishers[2].shm)

    # close file descriptors
    shm_close(pub_sub.publishers[1].shm)
    shm_close(pub_sub.publishers[2].shm)

    println("run finished")
end

run()
