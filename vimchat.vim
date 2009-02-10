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
import os, os.path, pynotify, select, threading, vim, xmpp
from datetime import time
from time import strftime

#Global Variables
chats = {}
chatServer = ""
chatMatches = {}
#}}}

#Classes
#{{{ class VimChat
class VimChat(threading.Thread):
    #Vim Executable to use
    _vim = 'vim'
    _rosterFile = '/tmp/vimChatRoster'
    _roster = {}

    #{{{ __init__
    def __init__(self, jid, jabberClient, roster, callbacks):
        self._jid = jid
        self._recievedMessage = callbacks
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

        print "Connected with VimChat (jid = " + self._jid + ")"

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
                    show = u'online'
                else:
                    show = u'offline'
            if not priority:
                priority = u''
            if not groups:
                groups = u''
            
            try:
                buddy =\
                    u"{{{ %s -- %s\n\t%s \n\tGroups: %s\n\t%s:\n%s\n}}}\n" %\
                    (name, show, item, groups, show, status)
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
        pass
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

#General Functions
#{{{ VimChatShowBuddyList
def vimChatShowBuddyList():
    global chatServer
    if not chatServer:
        print "Not Connected!  Please connect first."
        return 0

    #Write buddy list to file
    chatServer.writeRoster()

    rosterFile = chatServer._rosterFile
    buddyListWidth = vim.eval('g:vimchat_buddylistwidth')

    try:
        vim.command("silent vertical sview " + rosterFile)
        vim.command("silent wincmd H")
        vim.command("silent vertical resize " + buddyListWidth)
    except:
        vim.command("tabe " + rosterFile)

    vim.command("setlocal foldtext=VimChatFoldText()")
    vim.command("set nowrap")
    vim.command("set foldmethod=marker")
    vim.command("nmap <buffer> <silent> <Return> :py vimChatBeginChat()<CR>")
    vim.command("nnoremap <buffer> <silent> q :hide<CR>")
#}}}

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

#{{{ addBufMatch
def addBufMatch(buf, matchId):
    matchKeys = chatMatches.keys() 
    if buf in matchKeys:
        chatMatches[buf].append(matchId)
    else:
        chatMatches[buf] = []
        chatMatches[buf].append(matchId)
        
#}}}
#{{{ vimChatDeleteBufferMatches
def vimChatDeleteBufferMatches(buf):
    if buf in chatMatches.keys():
        for match in chatMatches[buf]:
            try:
                vim.command('call matchdelete(' + match + ')')
            except:
                pass

        chatMatches[buf] = []
#}}}

#{{{ vimChatBeginChat
def vimChatBeginChat():

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

    chatKeys = chats.keys()
    chatFile = ''
    if toJid in chatKeys:
        chatFile = chats[toJid]
    else:
        chatFile = toJid
        chats[toJid] = chatFile

    vim.command("hide")
    vim.command("split " + chatFile)

    vim.command("let b:buddyId = '" + toJid + "'")

    vimChatSetupChatBuffer();

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
    """
    vim.command(commands)

    vim.command('let b:id = ""')
    # This command has to be sent by itself.
    vim.command('au CursorMoved <buffer> py vimChatDeleteBufferMatches("' + \
        vim.current.buffer.name + '")')
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

#INCOMING
#{{{ vimChatMessageReceived
def vimChatMessageReceived(fromJid, message):
    origBufNum = vim.current.buffer.number

    #get timestamp
    tstamp = getTimestamp()

    user, domain = fromJid.split('@')
    jid = fromJid
    resource = ''
    try:
        jid, resource = jid.split('/')
    except:
        resource = ""

    chatKeys = chats.keys()
    chatFile = ''
    if jid in chatKeys:
        chatFile = chats[jid]
    else:
        chatFile = jid
        chats[jid] = chatFile

    vim.command("bad " + chatFile)
    try:
        vim.command("sbuffer " + chatFile)
    except:
        vim.command("new " + chatFile)

    vim.command("let b:buddyId = '" + fromJid + "'")

    vimChatSetupChatBuffer();

    lines = message.split("\n")
    line = lines.pop(0);
    toAppend = tstamp + " " + user + '/' + resource + ": " + line
    vimChatLog(jid, toAppend)
    vim.current.buffer.append(toAppend)

    pynotify.init('vimchat')
    n = pynotify.Notification(user + ' says:', message, 'dialog-warning')
    n.show()

    for line in lines:
        line = tstamp + '\t' + line
        vim.current.buffer.append(line)

    vim.command("let b:lastMatchId =  matchadd('Error', '\%' . line('$') . 'l')")
    lastMatchId = vim.eval('b:lastMatchId')
    addBufMatch(chatFile,lastMatchId)
    vim.command("normal G")
    vim.command("echo 'Message Received from: " + jid + "'")
    vim.command("sbuffer " + str(origBufNum))
#}}}
#{{{ vimChatLog
def vimChatLog(user, msg):
    logChats = int(vim.eval('g:vimchat_logchats'))
    if logChats > 0:
        logPath = vim.eval('g:vimchat_logpath')
        logDir = os.path.expanduser(logPath)
        if not os.path.exists(logDir):
            os.makedirs(logDir)

        day = strftime('%Y-%m-%d')
        log = open(logDir + '/' + user + '-' + day, 'a')
        log.write(msg + '\n')
        log.close()
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
    chatServer = VimChat(jid, jabberClient, roster, vimChatMessageReceived)
    chatServer.start()

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

EOF
" vim:et:fdm=marker:sts=4:sw=4:ts=4
