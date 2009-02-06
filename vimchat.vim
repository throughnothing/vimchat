com! VimessengerSignOff py signOff()
map <Leader>b :call VimessengerShowBuddyList()<CR>

set switchbuf=usetab
let g:rosterFile = '/tmp/vimchatBuddies'
highlight VimessengerDarkBlue guibg=darkblue guifg=white ctermbg=darkblue ctermfg=white
sign define VimessengerSignNewMsg linehl=VimessengerDarkBlue

"Internal (don't talk to the server)
"{{{ VimessengerShowBuddyList
function! VimessengerShowBuddyList()
    exe "bad " . g:rosterFile
    try
        exe "sbuffer" . g:rosterFile
    catch
        exe "tabe " . g:rosterFile
    endtry

    set nowrap

    nnoremap <buffer> <silent> <Return> :py vimessengerBeginChat()<CR>
endfunction
"}}}

python <<EOF
import vim
chats = {}

#{{{ vimessengerSetupChatBuffer
def vimessengerSetupChatBuffer():
    commands = """\
    setlocal noswapfile
    setlocal buftype=nowrite
    setlocal noai
    setlocal nocin
    setlocal nosi
    setlocal syntax=dcl
    setlocal wrap
    map <buffer> <Return> :py sendMessage()<CR>
    """
    vim.command(commands)

    # This command has to be sent by itself.
    vim.command('au CursorMoved <buffer> sign unplace *')
#}}}
#{{{ vimessengerBeginChat
def vimessengerBeginChat():

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

    vimessengerSetupChatBuffer();

#}}}

#OUTGOING

#{{{ sendMessage
def sendMessage():
    import vim,base64

    #toJid = vim.current.buffer.name
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

    msg = base64.encodestring('sendMessage:' + toJid + ':' + body)

    #vim.command("call VJSendString('" + msg + "')")
    sendString(msg)

    msg = str(vim.current.line)
    vim.current.line = "Me: " + msg
#}}}
#{{{ sendString
def sendString(msg):
    import socket,sys
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect(('localhost',2727))
    s.send(msg)
#}}}
#{{{ signOff
def signOff():
    try:
        #vim.command('call VJSendString("disconnect:")')
        sendString('disconnect:')
    except:
        vim.command('echo "Failed to sign off!"')

#}}}
#TODO: presenceUpdate()
EOF

"INCOMING (callbacks called from server)
"{{{ VJMessageReceived
function! VJMessageReceived(fromJid, message)
python <<EOF
import vim,base64

origBufNum = vim.current.buffer.number
fromJid = base64.decodestring(vim.eval('a:fromJid'))
message = base64.decodestring(vim.eval('a:message'))

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

vimessengerSetupChatBuffer();

messageLines = message.split("\n")
toAppend = user + '/' + resource + ": " + messageLines[0]
messageLines.pop(0)
vim.current.buffer.append(toAppend)

for line in messageLines:
    line = '\t' + line
    vim.current.buffer.append(line)

vim.command("normal G")

# Clear the last sign and add a new one notify user of new message.
vim.command('sign unplace 1')
vim.command('sign place 1 line=' + vim.eval('line("$")')
    + ' name=VimessengerSignNewMsg buffer='
    + str(vim.current.buffer.number))

# Switch back to the original buffer.
vim.command("sbuffer " + str(origBufNum))

EOF
endfunction
"}}}

" vim:et:fdm=marker:sts=4:sw=4:ts=4
