from logging import nil
import std/[uri, strutils, nativesockets]
import ./[serverlogger]
import ../private/[util]



when useAsync:
  import std/[asyncdispatch, asyncnet]
else:
  import std/[net]
  when useThreads:
    import std/[locks]


type
  RsyslogFacilities* = enum
    FAC_KERN       #  kernel messages
    FAC_USER       #  random user-level messages
    FAC_MAIL       #  mail system
    FAC_DAEMON     #  system daemons
    FAC_AUTH       #  security/authorization messages
    FAC_SYSLOG     #  messages generated internally by syslogd
    FAC_LPR        #  line printer subsystem
    FAC_NEWS       #  network news subsystem
    FAC_UUCP       #  UUCP subsystem
    FAC_CRON       #  clock daemon
    FAC_AUTHPRIV   #  security/authorization messages (private)
    FAC_FTP        #  FTP daemon
    FAC_NTP        #  NTP subsystem
    FAC_SECURITY   #  Log audit
    FAC_CONSOLE    #  Log alert
    FAC_SOLCRON    #  Scheduling daemon (Solaris)
    #  other codes through 15 reserved for system use
    FAC_LOCAL0      #  reserved for local use
    FAC_LOCAL1      #  reserved for local use
    FAC_LOCAL2      #  reserved for local use
    FAC_LOCAL3      #  reserved for local use
    FAC_LOCAL4      #  reserved for local use
    FAC_LOCAL5      #  reserved for local use
    FAC_LOCAL6      #  reserved for local use

  RsyslogLevels = enum
    LOG_EMERG       #  system is unusable
    LOG_ALERT       #  action must be taken immediately
    LOG_CRIT        #  critical conditions
    LOG_ERR         #  error conditions
    LOG_WARNING     #  warning conditions
    LOG_NOTICE      #  normal but significant condition
    LOG_INFO        #  informational
    LOG_DEBUG       #  debug-level messages

  RsysLoggerImpl = ref object of RootObj
    when useAsync:
      socket: AsyncSocket
    else:
      when useThreads:
        sLock: Lock
        socket {.guard: sLock.}: Socket
      else:
        socket: Socket
    useUnixSock: bool
    useTcpSock: bool
    host: string
    port: Port
    facility: RsyslogFacilities
    isConnected: bool

  RsyslogLogger* = ref object of ServerLogger
    impl: RsysLoggerImpl


when defined(macosx):
  const DEFAULT_URL = "unix:///var/run/syslog"
else:
  const DEFAULT_URL = "unix:///dev/log"



let convTable: array[logging.Level, RsyslogLevels] = [
  LOG_DEBUG, LOG_DEBUG, LOG_INFO, LOG_NOTICE, LOG_WARNING, LOG_ERR, LOG_EMERG, LOG_DEBUG
]


proc newRsyslogLogger*(
  url = DEFAULT_URL,
  facility: RsyslogFacilities = FAC_USER,
  levelThreshold = logging.lvlDebug,
  fmtStr = DEFAULT_FORMAT
): RsyslogLogger =
  result.new
  result.initLogger(levelThreshold, fmtStr)
  result.impl.new
  result.impl.facility = facility
  result.impl.isConnected = false
  let parsed = url.parseUri()
  case parsed.scheme
  of "unix":
    result.impl.host = parsed.path
    result.impl.useUnixSock = true
    result.impl.useTcpSock = false
  of "unix_tcp":
    result.impl.host = parsed.path
    result.impl.useUnixSock = true
    result.impl.useTcpSock = true
  of "udp":
    result.impl.host = parsed.hostname
    result.impl.port = parsed.port.parseBiggestInt().Port
    result.impl.useUnixSock = false
    result.impl.useTcpSock = false
  of "tcp":
    result.impl.host = parsed.hostname
    result.impl.port = parsed.port.parseBiggestInt().Port
    result.impl.useUnixSock = false
    result.impl.useTcpSock = true
  else:
    raise newException(ValueError, "Unsupported URL scheme: " & parsed.scheme)
  when useThreads:
    result.impl.sLock.initLock()


template encodePriority(facility: RsyslogFacilities, priority: RsyslogLevels): int = facility.int.shl(3) or priority.int


when useAsync:
  proc connectUnixSocket(self: RsyslogLogger) {.async.} =
    if not self.impl.isConnected:
      try:
        await self.impl.socket.connectUnix(self.impl.host)
        self.impl.isConnected = true
      except OSError:
        self.impl.socket.close()
        self.impl.isConnected = false
        raise

  proc connectNonUnix(self: RsyslogLogger) {.async.} =
    if not self.impl.isConnected:
      try:
        await self.impl.socket.connect(self.impl.host, self.impl.port)
        self.impl.isConnected = true
      except OSError:
        self.impl.socket.close()
        self.impl.isConnected = false
        raise

  method open*(self: RsyslogLogger, name: string) =
    proc realOpen() {.async.} =
      if self.impl.useUnixSock:
        self.impl.socket = newAsyncSocket(AF_UNIX, (if self.impl.useTcpSock: SOCK_STREAM else: SOCK_DGRAM), IPPROTO_NONE)
      elif self.impl.useTcpSock:
        self.impl.socket = newAsyncSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
      else:
        self.impl.socket = newAsyncSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered=false)
      if self.impl.useUnixSock:
        await self.connectUnixSocket()
      else:
        await self.connectNonUnix()
    waitFor(realOpen())
    self.install(name)

  method close*(self: RsyslogLogger) =
    if self.impl.isConnected:
      self.impl.socket.close()
      self.impl.isConnected = false
    self.deinstall()

  method log*(logger: RsyslogLogger, level: logging.Level, args: varargs[string, `$`]) =
    proc realsend(msg: string) {.async.} =
      if logger.impl.useUnixSock or logger.impl.useTcpSock:
        await logger.impl.socket.send(msg)
      else:
        await logger.impl.socket.sendTo(logger.impl.host, logger.impl.port, msg)
    if level >= logger.levelThreshold:
      let prio = encodePriority(logger.impl.facility, convTable[level])
      let msg: string = $prio & logger.buildMessage(level, args) & "\x00"
      if not logger.impl.isConnected:
        if logger.impl.useUnixSock:
          waitFor logger.connectUnixSocket()
        else:
          waitFor logger.connectNonUnix()
      try:
        waitFor(msg.realsend)
      except IOError:
        discard
else:
  proc connectUnixSocket(self: RsyslogLogger) =
    try:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.connectUnix(self.impl.host)
      self.impl.isConnected = true
    except OSError:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.close()
      self.impl.isConnected = false
      raise

  proc connectNonUnix(self: RsyslogLogger) =
    try:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.connect(self.impl.host, self.impl.port)
      self.impl.isConnected = true
    except OSError:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.close()
      self.impl.isConnected = false
      raise

  method open*(self: RsyslogLogger, name: string) =
    whenNeedLock(self.impl.sLock):
      if self.impl.useUnixSock:
        self.impl.socket = newSocket(AF_UNIX, (if self.impl.useTcpSock: SOCK_STREAM else: SOCK_DGRAM), IPPROTO_NONE)
      elif self.impl.useTcpSock:
        self.impl.socket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
      else:
        self.impl.socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP, buffered=false)
    if self.impl.useUnixSock:
      self.connectUnixSocket()
    else:
      self.connectNonUnix()
    self.install(name)

  method close*(self: RsyslogLogger) =
    if self.impl.isConnected:
      whenNeedLock(self.impl.sLock):
        self.impl.socket.close()
      self.impl.isConnected = false
    self.deinstall()

  method log*(logger: RsyslogLogger, level: logging.Level, args: varargs[string, `$`]) =
    if level >= logger.levelThreshold:
      let prio = encodePriority(logger.impl.facility, convTable[level])
      let msg: string = $prio & logger.buildMessage(level, args) & "\x00"
      if not logger.impl.isConnected:
        if logger.impl.useUnixSock:
          logger.connectUnixSocket()
        else:
          logger.connectNonUnix()
      try:
        if logger.impl.useUnixSock or logger.impl.useTcpSock:
          withNoLock(logger.impl.sLock):
            logger.impl.socket.send(msg)
        else:
          withNoLock(logger.impl.sLock):
            logger.impl.socket.sendTo(logger.impl.host, logger.impl.port, msg)
      except IOError:
        discard


proc clone*(self: RsyslogLogger): RsyslogLogger =
  result.new
  self.clone(result)
  result.impl = self.impl


