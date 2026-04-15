const useAsync* = defined(useAsync)
const useThreads* = compileOption("threads") and not useAsync
const DEFAULT_FORMAT* = "%(asctime).%(msecs) %(process) %(levelname) %(filename):%(lineno)] %(name) %(tags) %(message)"

when not useAsync:
  when useThreads:
    import std/[locks]

  template whenNeedLock*(l: Lock, body: untyped) =
    when useThreads:
      withLock(l):
        body
    else:
      body

  template withNoLock*(l: Lock, body: untyped) =
    when useThreads:
      {.locks: [l].}:
        body
    else:
      body
