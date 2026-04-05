import ../serverloggers
import std/[asyncdispatch]


proc useRsyslog() {.async.} =
  let logger: ServerLogger = newRsyslogLogger()
  logger.open()
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  logger.close()


waitFor(useRsyslog())
