module SPSCQueue

include("SPSCMessage.jl")
include("SPSCStorage.jl")
include("SPSCQueueVar.jl")

export SPSCStorage
export SPSCQueueVar, enqueue, dequeue, dequeue_commit!, buffer_size, max_message_size
export SPSCMessage, SPSCMessageView, total_size, payload_size, isempty

end # module
