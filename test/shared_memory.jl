using TestItems

@testitem "shared memory" begin
    using SPSCQueue.SharedMemory

    buffer_size = 1024 # bytes
    shm_size = buffer_size + SPSC_STORAGE_BUFFER_OFFSET

    # works only on Linux (see src/shm.jl for details)
    shm_fd, shm_size, shm_ptr = shm_open(
        "SPSCQueue_jl_shm_unit_test"
        ;
        shm_flags=Base.Filesystem.JL_O_CREAT |
                  Base.Filesystem.JL_O_RDWR |
                  Base.Filesystem.JL_O_TRUNC,
        shm_mode=0o666,
        size=shm_size
    )
    storage = SPSCStorage(shm_ptr, shm_size)
    queue = SPSCQueueVar(storage)

    unlink_shm("SPSCQueue_jl_shm_unit_test")
    close(shm_fd)
end

@testitem "shared memory reopen" begin
    using SPSCQueue.SharedMemory

    buffer_size = 1024 # bytes
    shm_size = buffer_size + SPSC_STORAGE_BUFFER_OFFSET

    # works only on Linux (see src/shm.jl for details)
    shm_fd, shm_size, shm_ptr = shm_open(
        "SPSCQueue_jl_shm_unit_test_reopen"
        ;
        shm_flags=Base.Filesystem.JL_O_CREAT |
                  Base.Filesystem.JL_O_RDWR |
                  Base.Filesystem.JL_O_TRUNC,
        shm_mode=0o666,
        size=shm_size,
        verbose=true
    )
    storage = SPSCStorage(shm_ptr, shm_size)
    queue = SPSCQueueVar(storage)

    # push 10 messages
    for i in 1:10
        data = [Float64(i)]
        GC.@preserve data begin
            ptr = reinterpret(Ptr{Float64}, pointer(data))
            @test enqueue!(queue, SPSCMessage(ptr, 1))
        end
    end

    # pop 3 messages
    for i in 1:3
        msg_view = dequeue_begin!(queue)
        @test !isempty(msg_view)
        dequeue_commit!(queue, msg_view)
    end

    # close shared memory, but keep the queue alive
    # unlink_shm("SPSCQueue_jl_shm_unit_test")
    close(shm_fd)

    # reopen shared memory
    # works only on Linux (see src/shm.jl for details)
    shm_fd, shm_size, shm_ptr2 = shm_open(
        "SPSCQueue_jl_shm_unit_test_reopen"
        ;
        shm_flags=Base.Filesystem.JL_O_RDWR,
        shm_mode=0o666,
        verbose=true
    )

    storage = SPSCStorage(shm_ptr2)
    println("read_ix: ", unsafe_load(storage.read_ix, :monotonic))
    println("write_ix: ", unsafe_load(storage.write_ix, :monotonic))
    @test unsafe_load(storage.read_ix, :monotonic) == 3*(8+8)
    @test unsafe_load(storage.write_ix, :monotonic) == 10*(8+8)
    @test storage.storage_size == shm_size
    @test storage.buffer_size == buffer_size

    queue = SPSCQueueVar(storage)
    @test queue.cached_read_ix == 3*(8+8)
    @test queue.cached_write_ix == 10*(8+8)
    @test can_dequeue(queue)
    @test !isempty(queue)

    # now destroy shared memory
    unlink_shm("SPSCQueue_jl_shm_unit_test_reopen")
    close(shm_fd)
end
