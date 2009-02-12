" VImChat Plugin for vim
" This plugin allows you to connect to a jabber server and chat with
" multiple people.
"
" It does not currently support other IM networks or group chat, but these are
" on the list to be added.
"
" It currently only supports one jabber account at a time
" 
" Supported ~/.vimrc Variables:
"   g:vimchat_jid = jabber id -- required
"   g:vimchat_password = jabber password -- required
"
"   g:vimchat_buddylistwidth = width of buddy list
"   g:vimchat_logpath = path to store log files
"   g:vimchat_logchats = (0 or 1) default is 1
"
"


if exists('g:vimchat_loaded')
    finish
endif
let g:vimchat_loaded = 1


"Vim Commands
"{{{ Vim Commands
com! VimChat py vimChatSignOn()
com! VimChatSignOn py vimChatSignOn()
com! VimChatSignOff py vimChatSignOff()
com! VimChatShowBuddyList py vimChatShowBuddyList()

"Connect to jabber
map <Leader>vcc :silent py vimChatSignOn()<CR>
"Disconnect from jabber
map <Leader>vcd :silent py vimChatSignOff()<CR>

set switchbuf=usetab
"}}}


"Vim Functions
"{{{ VimChatCheckVars
fu! VimChatCheckVars()
    if !exists('g:vimchat_jid')
        echo "Must set g:vimchat_jid in ~/.vimrc!"
        return 0
    endif
    if !exists('g:vimchat_password')
        echo "Must set g:vimchat_password in ~/.vimrc!"
        return 0
    endif
    if !exists('g:vimchat_buddylistwidth')
        let g:vimchat_buddylistwidth=30
    endif
    if !exists('g:vimchat_logpath')
        let g:vimchat_logpath="~/.vimchat/logs"
    endif
    if !exists('g:vimchat_logchats')
        let g:vimchat_logchats=1
    endif

    return 1
endfu
"}}}
"{{{ VimChatFoldText
function! VimChatFoldText()
    let line=substitute(getline(v:foldstart),'^[ \t#]*\([^=]*\).*', '\1', '')
    let line=strpart('                                     ', 0, (v:foldlevel - 1)).substitute(line,'\s*{\+\s*', '', '')
    return line
endfunction
"}}}

""""""""""Python Stuff""""""""""""""
python <<EOF
#Imports/Global Vars
#{{{ imports/global vars
import os, os.path, select, threading, vim, xmpp
from datetime import time
from time import strftime

try:
    import pynotify
    pynotify_enabled = True
except:
    print "pynotify missing...no notifications will occur!"
    pynotify_enabled = False


#Global Variables
chats = {}
chatServer = ""
#}}}

#CLASSES
#{{{ class VimChat
class VimChat(threading.Thread):
    #Vim Executable to use
    _vim = 'vim'
    _rosterFile = '/tmp/vimChatRoster'
    _roster = {}
    buddyListBuffer = None

    #{{{ __init__
    def __init__(self, jid, jabberClient, roster, callbacks):
        self._jid = jid
        self._recievedMessage = callbacks['message']
        self._presenceCallback = callbacks['presence']
        self._roster = roster
        threading.Thread.__init__ ( self )
        self.jabber = jabberClient
    #}}}
    #{{{ run
    def run(self):
        self.jabber.RegisterHandler('message',self.jabberMessageReceive)
        self.jabber.RegisterHandler('presence',self.jabberPresenceReceive)

        #Socket stuff
        RECV_BUF = 4096
        self.xmppS = self.jabber.Connection._sock
        socketlist = [self.xmppS]
        online = 1


        while online:
            (i , o, e) = select.select(socketlist,[],[],1)
            for each in i:
                if each == self.xmppS:
                    self.jabber.Process(1)
                else:
                    pass
    #}}}

    #Roster Stuff
    #{{{ writeRoster
    def writeRoster(self):
        #write roster to file
        rosterItems = self._roster.getItems()
        rosterItems.sort()
        import codecs
        rF = codecs.open(self._rosterFile,'w','utf-16')

        for item in rosterItems:
            name = self._roster.getName(item)
            status = self._roster.getStatus(item)
            show = self._roster.getShow(item)
            priority = self._roster.getPriority(item)
            groups = self._roster.getGroups(item)

            if not name:
                name = item
            if not status:
                status = u''
            if not show:
                if priority:
                    show = u'on'
                else:
                    show = u'off'
            if not priority:
                priority = u''
            if not groups:
                groups = u''
            
            try:
                buddy =\
                    u"{{{ (%s) %s\n\t%s \n\tGroups: %s\n\t%s:\n%s\n}}}\n" %\
                    (show, name, item, groups, show, status)
                rF.write(buddy)
            except:
                pass

        rF.close()
    #}}}

    #From Jabber Functions
    #{{{ jabberMessageReceive
    def jabberMessageReceive(self, conn, msg):
        if msg.getBody():
            fromJid = str(msg.getFrom())
            body = str(msg.getBody())

            self._recievedMessage(fromJid, body)
    #}}}
    #{{{ jabberPresenceReceive
    def jabberPresenceReceive(self, conn, msg):
        fromJid = msg.getFrom()
        show = msg.getShow()
        status = msg.getStatus()
        priority = msg.getPriority()

        if not show:
            if priority:
                show = 'online'
            else:
                show = 'offline'

        self._presenceCallback(fromJid,show,status,priority)
    #}}}

    #To Jabber Functions
    #{{{ jabberSendMessage
    def jabberSendMessage(self, tojid, msg):
        msg = msg.strip()
        m = xmpp.protocol.Message(to=tojid,body=msg,typ='chat')
        self.jabber.send(m)
    #}}}
    #{{{ jabberPresenceUpdate
    def jabberPresenceUpdate(self, show, status):
        m = xmpp.protocol.Presence(
            self._jid,
            show=show,
            status=status)
        self.jabber.send(m)
    #}}}
    #{{{ disconnect
    def disconnect(self):
        try:
            self.jabber.disconnect()
        except:
            pass
    #}}}

    #Roster Functions
    #{{{ getRosterItems
    def getRosterItems(self):
        if self._roster:
            return self._roster.getItems()
        else:
            return None
    #}}}
#}}}

#HELPER FUNCTIONS
#{{{ getTimestamp
def getTimestamp():
    return strftime("[%H:%M]")
#}}}
#{{{ getBufByName
def getBufByName(name):
    for buf in vim.buffers:
        if buf.name == name:
            return buf
    return None
#}}}

#BUDDY LIST
#{{{ VimChatShowBuddyList
def vimChatShowBuddyList():
    # godlygeek's way to determine if a buffer is hidden in one line:
    #:echo len(filter(map(range(1, tabpagenr('$')), 'tabpagebuflist(v:val)'), 'index(v:val, 4) == 0'))

    global chatServer
    if not chatServer:
        print "Not Connected!  Please connect first."
        return 0

    if chatServer.buddyListBuffer:
        bufferList = vim.eval('tabpagebuflist()')
        if str(chatServer.buddyListBuffer.number) in bufferList:
            vim.command('sbuffer ' + str(chatServer.buddyListBuffer.number))
            print 'going to hide buffer'
            vim.command('hide')
            return

    #Write buddy list to file
    chatServer.writeRoster()

    rosterFile = chatServer._rosterFile
    buddyListWidth = vim.eval('g:vimchat_buddylistwidth')

    try:
        vim.command("silent vertical sview " + rosterFile)
        vim.command("silent wincmd H")
        vim.command("silent vertical resize " + buddyListWidth)
        vim.command("silent e!")
        vim.command("setlocal noswapfile")
        vim.command("setlocal buftype=nowrite")
    except:
        vim.command("tabe " + rosterFile)

    chatServer.buddyListBuffer = vim.current.buffer

    vim.command("setlocal foldtext=VimChatFoldText()")
    vim.command("set nowrap")
    vim.command("set foldmethod=marker")
    vim.command(
        "nmap <buffer> <silent> <CR> :py vimChatBeginChatFromBuddyList()<CR>")
    vim.command("nnoremap <buffer> <silent> q :hide<CR>")
    vim.command("nnoremap <buffer> <silent> L :py vimChatOpenLog()<CR>")
#}}}
#{{{ vimChatGetBuddyListItem
def vimChatGetBuddyListItem(item):
    if item == 'jid':
        vim.command('let b:getLine = getline(".")=~"{\|}"')
        getLine = vim.eval('b:getLine')
        vim.command('let b:foldClosed = foldclosed(".")')
        foldClosed = vim.eval('b:foldClosed')

        if int(foldClosed) == -1:
            #If the fold is not closed
            vim.command("normal! ]z")
            vim.command("normal! [z")
            vim.command("normal! j")
        else:
            #If the fold is closed
            vim.command("normal! za")
            vim.command("normal! j")


        toJid = vim.current.line
        toJid = toJid.strip()
        return toJid

#}}}
#{{{ vimChatBeginChatFromBuddyList
def vimChatBeginChatFromBuddyList():
    toJid = vimChatGetBuddyListItem('jid')
    #Just in case
    toJid = toJid.split('/')[0]

    #Hid Buddy list
    vim.command("hide")
    buf = vimChatBeginChat(toJid)
    vim.command('sbuffer ' + str(buf.number))
#}}}

#CHAT BUFFERS
#{{{ vimChatBeginChat
def vimChatBeginChat(toJid):
    #Set the ChatFile
    if toJid in chats.keys():
        chatFile = chats[toJid]
    else:
        chatFile = toJid
        chats[toJid] = chatFile

    bExists = int(vim.eval('bufexists("' + chatFile + '")'))
    if bExists: 
        return getBufByName(chatFile)
    else:
        vim.command("split " + chatFile)
        #Only do this stuff if its a new buffer
        vim.command("let b:buddyId = '" + toJid + "'")
        vimChatSetupChatBuffer();
        return vim.current.buffer

#}}}
#{{{ vimChatSetupChatBuffer
def vimChatSetupChatBuffer():
    commands = """\
    setlocal noswapfile
    setlocal buftype=nowrite
    setlocal noai
    setlocal nocin
    setlocal nosi
    setlocal syntax=dcl
    setlocal wrap
    nnoremap <buffer> i :py vimChatSendBufferShow()<CR>
    nnoremap <buffer> o :py vimChatSendBufferShow()<CR>
    nnoremap <buffer> B :py vimChatShowBuddyList()<CR>
    nnoremap <buffer> q :silent hide<CR>
    """
    vim.command(commands)
#}}}
#{{{ vimChatSendBufferShow
def vimChatSendBufferShow():
    toJid = vim.eval('b:buddyId')

    origBuf = vim.current.buffer.name
    chats[toJid]= origBuf

    #Create sending buffer
    sendBuffer = "sendTo:" + toJid
    vim.command("silent bo new " + sendBuffer)
    vim.command("silent let b:buddyId = '" + toJid +  "'")

    commands = """\
        resize 4
        setlocal noswapfile
        setlocal nocin
        setlocal noai
        setlocal nosi
        setlocal buftype=nowrite
        setlocal wrap
        noremap <buffer> <CR> :py vimChatSendMessage()<CR>
        inoremap <buffer> <CR> <Esc>:py vimChatSendMessage()<CR>
        nnoremap <buffer> q :hide<CR>
    """
    vim.command(commands)
    vim.command('normal G')
    vim.command('normal o')
    vim.command('normal zt')
    vim.command('star')

#}}}
#{{{ vimChatAppendMessage
def vimChatAppendMessage(buf, message):
    if not buf:
        print "VimChat: Invalid Buffer to append to!"
        return 0

    lines = message.split("\n")

    #Get the first line
    line = lines.pop(0);
    buf.append(line)

    for line in lines:
        line = '\t' + line
        buf.append(line)
#}}}

#NOTIFY
#{{{ vimChatNotify
def vimChatNotify(title, msg, type):
    #Do this so we can work without pynotify
    if pynotify_enabled:
        pynotify.init('vimchat')
        n = pynotify.Notification(title, msg, type)
        n.set_timeout(5000)
        n.show()
#}}}

#LOGGING
#{{{ vimChatLog
def vimChatLog(user, msg):
    logChats = int(vim.eval('g:vimchat_logchats'))
    if logChats > 0:
        logPath = vim.eval('g:vimchat_logpath')
        logDir = os.path.expanduser(logPath + '/' + user)
        if not os.path.exists(logDir):
            os.makedirs(logDir)

        day = strftime('%Y-%m-%d')
        log = open(logDir + '/' + user + '-' + day, 'a')
        log.write(msg + '\n')
        log.close()
#}}}
#{{{ vimChatOpenLog
def vimChatOpenLog():
    user = vimChatGetBuddyListItem('jid')
    logPath = vim.eval('g:vimchat_logpath')
    logDir = os.path.expanduser(logPath + '/' + user)
    if not os.path.exists(logDir):
        print "No Logfile Found"
        return 0
    else:
        vim.command('silent tabe ' + logDir)

#}}}

#OUTGOING
#{{{ vimChatSendMessage
def vimChatSendMessage():
    try:
        toJid = vim.eval('b:buddyId')
    except:
        print "No valid chat found!"
        return 0

    tstamp = getTimestamp()
    chatBuf = getBufByName(chats[toJid])
    if not chatBuf:
        print "Chat Buffer Could not be found!"
        return 0

    jid = toJid.split('/')[0]

    r = vim.current.range
    body = ""
    for line in r:
        line = line.rstrip('\n')
        if body == "":
            chatBuf.append(tstamp + " Me: " + line)
            vimChatLog(jid, tstamp + " Me: " + line)
        else:
            chatBuf.append(tstamp + "\t" + line)
            vimChatLog(jid, tstamp + "\t" + line)

        body = body + line + '\n'

    global chatServer
    chatServer.jabberSendMessage(toJid, body)


    vim.command('hide')
    vim.command('sbuffer ' + str(chatBuf.number))
    vim.command('normal G')
#}}}
#{{{ vimChatSignOn
def vimChatSignOn():
    global chatServer
    vim.command('nnoremap <buffer> B :py vimChatShowBuddyList()<CR>')

    vim.command('let s:hasVars = VimChatCheckVars()')
    hasVars = int(vim.eval('s:hasVars'))

    if hasVars < 1:
        print "Could not start VimChat!"
        return 0

    if chatServer:
        print "Already connected to VimChat!"
        return 0
    else:
        print "Connecting..."

    jid = vim.eval('g:vimchat_jid')
    password = vim.eval('g:vimchat_password')

    JID=xmpp.protocol.JID(jid)
    jabberClient = xmpp.Client(JID.getDomain(),debug=[])

    con = jabberClient.connect()
    if not con:
        print 'could not connect!\n'
        return 0

    auth=jabberClient.auth(JID.getNode(), password, resource=JID.getResource())

    if not auth:
        print 'could not authenticate!\n'
        return 0

    jabberClient.sendInitPresence(requestRoster=1)
    roster = jabberClient.getRoster()
    callbacks = {
        'message':vimChatMessageReceived,
        'presence':vimChatPresenceUpdate}

    chatServer = VimChat(jid, jabberClient, roster, callbacks)
    chatServer.start()

    print "Connected with VimChat (" + jid + ")"

    vimChatShowBuddyList()
    
#}}}
#{{{ vimChatSignOff
def vimChatSignOff():
    global chatServer
    if chatServer:
        try:
            chatServer.disconnect()
            print "Signed Off VimChat!"
        except Exception, e:
            print "Error signing off VimChat!"
            print e
    else:
        print "Not Connected!"
#}}}

#INCOMING
#{{{ vimChatPresenceUpdate
def vimChatPresenceUpdate(fromJid, show, status, priority):
    #Only care if we have the chat window open
    fromJid = str(fromJid).split('/')[0]

    if fromJid in chats.keys():
        chatBuf = getBufByName(chats[fromJid])
        if chatBuf:
            #fromJid = str(fromJid.split('/')[0])
            #print "PresenceUpdate: " + str(fromJid) + " : " + str(show)
            #get the buffer of the chat
            tstamp = getTimestamp()
            statusUpdateLine = \
                tstamp + " -- " + str(fromJid) + \
                " is " + str(show) + ": " + str(status)

            chatBuf.append(statusUpdateLine)
        else:
            print "Buffer did not exist for: " + fromJid

#}}}
#{{{ vimChatMessageReceived
def vimChatMessageReceived(fromJid, message):
    #Store the buffer we were in
    origBufNum = vim.current.buffer.number

    jidParts = fromJid.split('/')
    jid = jidParts[0]
    user = jid.split('@')[0]

    #Get A Resource if exists
    if len(jidParts) > 1:
        resource = jidParts[1]
    else:
        resource = ''

    buf = vimChatBeginChat(jid)

    #get timestamp
    tstamp = getTimestamp()
    fullMessage = tstamp + " " + user + '/' + resource + ": " + message

    #Append Message to File
    vimChatAppendMessage(buf, fullMessage)

    #Log the message
    vimChatLog(jid, fullMessage)

    #Notify
    print "Message Received from: " + jid
    vimChatNotify(user + ' says:', message, 'dialog-warning')
#}}}


EOF
" vim:et:fdm=marker:sts=4:sw=4:ts=4
