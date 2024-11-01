module SPSCQueue

include("Memory.jl")
include("SharedMemory.jl")
include("SPSCMessage.jl")
include("SPSCStorage.jl")
include("SPSCQueueVar.jl")

export Memory
export SharedMemory
export SPSCStorage, SPSC_STORAGE_BUFFER_OFFSET
export SPSCQueueVar, enqueue!, dequeue_begin!, dequeue_commit!, buffer_size, max_message_size, can_dequeue
export SPSCMessage, SPSCMessageView, total_size, payload_size, isempty, SPSC_MESSAGE_VIEW_EMPTY

end # module
