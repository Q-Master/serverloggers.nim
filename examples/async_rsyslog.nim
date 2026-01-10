import ../serverloggers
import std/[asyncdispatch]


proc useRsyslog() {.async.} =
  let logger = newRsyslogLogger()
  await logger.open()
  logger.tag("key", "value")
  logger.tag("key1", 8)
  log(lvlDebug, "Test log")
  await logger.close()


waitFor(useRsyslog())
