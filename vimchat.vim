" VImChat Plugin for vim
" This plugin allows you to connect to a jabber server and chat with
" multiple people.
"
" It does not currently support other IM networks or group chat, but these are
" on the list to be added.
"
" It currently only supports one jabber account at a time
" 

com! VimChatSignOff py vimChatSignOff()
com! VimChatSignOn py vimChatSignOn()
com! VimChatShowBuddyList :call VimChatShowBuddyList()

"Show the buddy list
map <Leader>vcb :call VimChatShowBuddyList()<CR>
"Connect to jabber
map <Leader>vcc :silent py vimChatSignOn()<CR>
"Disconnect from jabber
map <Leader>vcd :silent py vimChatSignOn()<CR>

set switchbuf=usetab
let g:rosterFile = '/tmp/vimChatRoster'

"Vim Functions
"{{{ VimChatShowBuddyList
function! VimChatShowBuddyList()
    exe "bad " . g:rosterFile
    try
        exe "sbuffer" . g:rosterFile
    catch
        exe "tabe " . g:rosterFile
    endtry

    set nowrap

    nnoremap <buffer> <silent> <Return> :py vimChatBeginChat()<CR>
endfunction
"}}}


python <<EOF
import vim
import vim,xmpp,select,threading

#Global Variables
chats = {}
chatServer = ""
highlights = []

#{{{ class VimChat
class VimChat(threading.Thread):
    #Vim Executable to use
    _vim = 'vim'
    _rosterFile = '/tmp/vimChatRoster'
    _roster = {}

    #{{{ __init__
    def __init__(self, jid, password, callbacks):
        self._jid = jid
        self._password = password
        self._recievedMessage = callbacks
        threading.Thread.__init__ ( self )
    #}}}
    #{{{ _writeRoster
    def _writeRoster(self):
        #write roster to file
        rF = open(self._rosterFile,'w')
        for item in self._roster.keys():
            name = str(item)
            priority = self._roster[item]['priority']
            show = self._roster[item]['show']
            if name and priority and show:
                try:
                    #TODO: figure out unicode stuff here
                    rF.write(name + "\n")
                except:
                    rF.write(name + "\n")

            else:
                rF.write(name + "\n")
                #rF.write("{{{ " + item + "\n" + item + "\n}}}\n")

        rF.close()
    #}}}
    #{{{ _clearRoster
    def _clearRoster(self,string):
        #write roster to file
        rF = open(self._rosterFile,'w')
        rF.write(string)
        rF.close()
    #}}}

    #{{{ run
    def run(self):
        jid=xmpp.protocol.JID(self._jid)
        self.jabber =xmpp.Client(jid.getDomain(),debug=[])

        con=self.jabber.connect()
        if not con:
            sys.stderr.write('could not connect!\n')
            sys.exit(1)

        auth=self.jabber.auth(
            jid.getNode(),
            self._password,
            resource=jid.getResource())

        if not auth:
            sys.stderr.write('could not authenticate!\n')
            sys.exit(1)

        self.jabber.RegisterHandler('message',self.jabberMessageReceive)
        self.jabber.RegisterHandler('presence',self.jabberPresenceReceive)
        self.jabber.sendInitPresence(requestRoster=1)

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

    #From Jabber Functions
    #{{{ jabberMessageReceive
    def jabberMessageReceive(self, conn, msg):
        if msg.getBody():
            fromJid = str(msg.getFrom())
            body = str(msg.getBody())

            print "Message Received!"

            self._recievedMessage(fromJid, body)
    #}}}
    #{{{ jabberPresenceReceive
    def jabberPresenceReceive(self, conn, msg):
        jid = str(msg.getFrom())
        try:
            jid, resource = jid.split('/')
        except:
            resourc = ""

        try:
            oldPriority = self._roster[jid]['priority']
        except:
            oldPriority = None

        newPriority = msg.getPriority()
        self._roster[jid] = {'priority': newPriority,'show':msg.getShow()}
        self._writeRoster()
    #}}}

    #To Jabber Functions
    #{{{ jabberSendMessage
    def jabberSendMessage(self, tojid, msg):
        msg = msg.strip()
        m = xmpp.protocol.Message(to=tojid,body=msg,typ='chat')
        #print 'Message: ' + msg
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
        self._clearRoster("You are currently signed out of VimChat")
    #}}}
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
    map <buffer> <C-m>s :py vimChatSendMessage()<CR>
    """
    vim.command(commands)

#}}}
#{{{ vimChatBeginChat
def vimChatBeginChat():

    toJid = vim.current.line
    toJid = toJid.strip()


    user, domain = toJid.split('@')

    jid = toJid
    resource = ''
    if jid.find('/') >= 0:
        jid, resource = jid.split('/')

    chatKeys = chats.keys()
    chatFile = ''
    if toJid in chatKeys:
        chatFile = chats[toJid]
    else:
        chatFile = jid
        chats[toJid] = chatFile

    vim.command("bad " + chatFile)
    vim.command("e " + chatFile)

    vim.command("let b:buddyId = '" + toJid + "'")

    vimChatSetupChatBuffer();

#}}}
#{{{ vimChatDeleteLastMatch
def vimChatDeleteLastMatch():
    bid = vim.eval('b:id')
    if bid:
        bid = vim.eval('b:id')
        vim.command('call matchdelete(' + bid + ')')
#}}}

#OUTGOING
#{{{ vimChatSendMessage
def vimChatSendMessage():
    try:
        toJid = vim.eval('b:buddyId')
    except:
        print "No chat found!"
        return 0

    origBuf = vim.current.buffer.name
    origBuf = origBuf.split('/')
    origBuf = origBuf[len(origBuf) - 1]

    chatKeys = chats.keys()
    chats[toJid]= origBuf

    r = vim.current.range
    body = ""
    for line in r:
        line = line.rstrip('\n')
        body = body + line + '\n'

    global chatServer
    chatServer.jabberSendMessage(toJid, body)

    msg = str(vim.current.line)
    vim.current.line = "Me: " + msg
#}}}

#INCOMING
#{{{ vimChatMessageReceived
def vimChatMessageReceived(fromJid, message):
    origBufNum = vim.current.buffer.number

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

    messageLines = message.split("\n")
    toAppend = user + '/' + resource + ": " + messageLines[0]
    messageLines.pop(0)
    vim.current.buffer.append(toAppend)

    for line in messageLines:
        line = '\t' + line
        vim.current.buffer.append(line)

    vim.command("echo 'Message Received from: " + jid + "'")
    vim.command("sbuffer " + str(origBufNum))
#}}}

#{{{ vimChatSignOn
def vimChatSignOn():
    global chatServer

    if chatServer:
        print "Already connected to VimChat!"
        return 0

    jid = vim.eval('g:vimchat_jid')
    password = vim.eval('g:vimchat_password')

    chatServer = VimChat(jid, password,vimChatMessageReceived)
    chatServer.start()
    
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
