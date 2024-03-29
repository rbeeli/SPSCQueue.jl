using TestItems
using SPSCQueue
using TestItemRunner

@testitem "Init on heap memory" begin
    buffer_size = 1024 # bytes
    storage = SPSCStorage(buffer_size)
    queue = SPSCQueueVar(storage)
end


@testitem "enqueue dequeue isempty can_dequeue" begin
    buffer_size = 1024 # bytes
    storage = SPSCStorage(buffer_size)
    queue = SPSCQueueVar(storage)

    @test isempty(queue)
    @test !can_dequeue(queue)

    # enqueue
    data = [1, 2, 3, 4, 5]
    GC.@preserve data begin
        size_bytes = length(data) * sizeof(eltype(data))
        ptr = reinterpret(Ptr{UInt8}, pointer(data))
        msg = SPSCMessage(ptr, size_bytes)
        enqueue!(queue, msg)

        @test !isempty(queue)
        @test can_dequeue(queue)

        # dequeue
        msg_view = dequeue!(queue)
        @test msg_view.size == size_bytes
        for i in 1:msg_view.size
            @test unsafe_load(msg_view.data, i) == unsafe_load(ptr, i)
        end
        dequeue_commit!(queue, msg_view)
    end

    @test isempty(queue)
    @test !can_dequeue(queue)
end

@testitem "shared memory" begin
    include("shm.jl"); # include POSIX shared memory code

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

@run_package_tests
