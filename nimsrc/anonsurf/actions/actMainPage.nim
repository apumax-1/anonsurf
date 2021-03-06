import gintro / [gtk, glib, vte]
import .. / modules / [myip, torPorts]
import .. / displays / noti
import strutils
import net
import strscans
import system
import os

type
  MyIP = object
    thisAddr*: string
    isUnderTor*: string
    iconName*: string

var
  worker*: system.Thread[void]
  channel*: Channel[MyIP]

channel.open()

proc doCheckIP() =
  #[
    Actual IP check for AnonSurf
    It parses data from server and show notification
  ]#

  var finalResult: MyIP
  let ipInfo = checkIPFromTorServer()
  # If program has error while getting IP address
  if ipInfo[0].startsWith("Error"):
    finalResult.iconName = "error"
  # If program runs but user didn't connect to tor
  elif ipInfo[0].startsWith("Sorry"):
    finalResult.iconName = "security-medium"
  # Connected to tor
  else:
    finalResult.iconName = "security-high"

  finalResult.isUnderTor = ipInfo[0]
  finalResult.thisAddr = ipInfo[1]
  channel.send(finalResult) # Crash second time


proc onClickCheckIP*(b: Button) =
  #[
    Display IP when user click on CheckIP button
    Show the information in system's notification
  ]#
  sendNotify("My IP", "Getting data from server", "dialog-information")
  # channel.open()
  createThread(worker, doCheckIP)


proc onClickRun*(b: Button) =
  #[
    Create condition to Start / Stop AnonSurf when click on btn1
  ]#
  if b.label == "Start":
    discard spawnCommandLineAsync("gksudo /usr/bin/anonsurf start")
  else:
    discard spawnCommandLineAsync("gksudo /usr/bin/anonsurf stop")


proc onClickChangeID*(b: Button) =
  #[
    Use control port to change ID of Tor network
    1. Read password from nyxrc
    2. Get ControlPort from Torrc
    3. Send authentication request + NewNYM command
  ]#
  let conf = "/etc/anonsurf/nyxrc"
  if fileExists(conf):
    var
      tmp, passwd: string
      sock = net.newSocket()
    
    if scanf(readFile(conf), "$w $w", tmp, passwd):
      let controlPort = getTorrcPorts().controlPort
      # sock.connect("127.0.0.1", Port(9051))
      if ":" in controlPort:
        sock.connect("127.0.0.1", Port(parseInt(controlPort.split(":")[1])))
      else:
        sock.connect("127.0.0.1", Port(parseInt(controlPort)))
      sock.send("authenticate \"" & passwd & "\"\nsignal newnym\nquit\n")
      let recvData = sock.recv(256).split("\n")
      sock.close()
      # Check authentication status
      if recvData[0] != "250 OK\c":
        sendNotify(
          "Identity Change Error",
          recvData[0],
          "error"
        )
        return
      # Check command status
      if recvData[1] != "250 OK\c":
        sendNotify(
          "Identity Change Error",
          recvData[1],
          "error"
        )
        return
      # Success. Show okay
      sendNotify(
        "Identity Change Success",
        "You have a new identity",
        "security-high"
      )
    else:
      sendNotify(
        "Identity Change Error",
        "Can parse settings",
        "error"
      )
  else:
    sendNotify(
        "Identity Change Error",
        "File not found",
        "error"
      )


proc onClickTorStatus*(b: Button) =
  #[
    Spawn a native GTK terminal and run nyx with it to show current tor status
  ]#
  let
    statusDialog = newDialog()
    statusArea = statusDialog.getContentArea()
    nyxTerm = newTerminal()

  statusDialog.setTitle("Tor bandwidth")

  nyxTerm.spawnAsync(
    {noLastlog}, # pty flags
    nil, # working directory
    ["/usr/bin/nyx", "--config", "/etc/anonsurf/nyxrc"], # args
    [], # envv
    {doNotReapChild}, # spawn flag
    nil, # Child setup
    nil, # child setup data
    nil, # chlid setup data destroy
    -1, # timeout
    nil, # cancellabel
    nil, # callback
    nil, # pointer
  )

  statusArea.packStart(nyxTerm, false, true, 3)
  statusDialog.showAll()
