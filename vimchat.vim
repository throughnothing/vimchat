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
"   g:vimchat_otr = (0 or 1) default is 1
"   g:vimchat_logotr = (0 or 1) default is 1
"

"{{{ Vim Commands
if exists('g:vimchat_loaded')
    finish
endif
let g:vimchat_loaded = 1

com! VimChat py vimChatSignOn()
com! VimChatSignOn py vimChatSignOn()
com! VimChatSignOff py vimChatSignOff()
com! VimChatBuddyList py vimChatToggleBuddyList()
com! VimChatViewLog py vimChatOpenLogFromChat()
com! VimChatJoinGroupChat py vimChatOpenGroupChat()
com! VimChatOtrVerifyBuddy py vimChatOtrVerifyBuddy()
com! VimChatOtrSMPRespond py vimChatOtrSMPRespond()
com! VimChatOtrGenerateKey py vimChatOtrGenerateKey()
com! VimChatSetStatus py vimChatSetStatus()
com! VimChatShowStatus py vimChatShowStatus()

set switchbuf=usetab
"}}}
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
    if !exists('g:vimchat_otr')
        let g:vimchat_otr=1
    endif
    if !exists('g:vimchat_logotr')
        let g:vimchat_logotr=1
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

python <<EOF
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

try:
    import otr
    pyotr_logging = True
    pyotr_enabled = True
except:
    pyotr_enabled = False
    pyotr_logging = False

#Global Variables
chats = {}
presence = ""
chatServer = ""
otr_basedir = '~/.vimchat/otr'
otr_keyfile = 'otrkey'
otr_fingerprints = 'fingerprints'
#}}}

#CLASSES
#{{{ class OtrOps
class OtrOps:
    #{{{ policy
    def policy(self, opdata=None, context=None):
        """ checks for the contacts username in policylist and returns it
        if available, otherwise checks for a default entry and returns it
        if available, otherwise just return python-otr's default """
        return otr.OTRL_POLICY_DEFAULT
    #}}}
    #{{{ create_privkey
    def create_privkey(self, opdata=None, accountname=None, protocol=None):
        # should give the user some visual feedback here, generating can take some time!
        # the private key MUST be available when this method returned
        print "need key for: " + accountname
        vimChatOtrGenerateKey() 
    #}}}
    #{{{ is_logged_in
    def is_logged_in(self, opdata=None, accountname=None, protocol=None, recipient=None):
        if recipient and chatServer:
            priority = chatServer._roster.getPriority(recipient)
            if priority:
                return True
            return False
        else:
            print "Error in is_logged_in"
            return False
    #}}}
    #{{{ inject_message	
    def inject_message(self, opdata=None, accountname=None, protocol=None, recipient=None, message=None):
        if recipient and message and chatServer:
            chatServer.jabberSendMessage(recipient, message)
        else:
            print "Error in inject_message"
    #}}}
    #{{{ notify
    def notify(sef, opdata=None, level=None, accountname=None, protocol=None, username=None, title=None, primary=None, secondary=None):
        # show a small dialog or something like that
        # level is otr.OTRL_NOTIFY_ERROR, otr.OTRL_NOTIFY_WARNING or otr.OTRL_NOTIFY_INFO
        # primary and secondary are the messages that should be displayed
        print "Notify: title: " + title + " primary: " + primary + \
            " secondary: " + secondary
    #}}}
    #{{{ display_otr_message
    def display_otr_message(self, opdata=None, accountname=None, protocol=None, username=None, msg=None):
        # this usually logs to the conversation window

        #write_message(our_account=accountname, proto=protocol, contact=username, message=msg)
        # NOTE: this function MUST return 0 if it processed the message
        # OR non-zero, the message will then be passed to notify() by OTR
        return 0
    #}}}
    #{{{ update_context_list
    def update_context_list(self, opdata=None):
        # this method may provide some visual feedback when the context list was updated
        # this may be useful if you have a central way of setting fingerprints' trusts
        # and you want to update the list of contexts to consider in this way
        pass
    #}}}
    #{{{ protocol_name
    def protocol_name(self, opdata=None, protocol=None):
        """ returns a "human-readable" version of the given protocol """
        if protocol == "xmpp":
        	return "XMPP (eXtensible Messaging and Presence Protocol)"
    #}}}
    #{{{ new_fingerprint
    def new_fingerprint(
        self, opdata=None, userstate=None, accountname=None,
        protocol=None, username=None, fingerprint=None):
        
        human_fingerprint = ""
        try:
            human_fingerprint = otr.otrl_privkey_hash_to_human(fingerprint)
            print "New Fingerprint"
            #write_message(our_account=accountname, proto=protocol, contact=username,
            #   message="New fingerprint: %s"%human_fingerprint)
            return human_fingerprint
        except:
            pass
    #}}}
    #{{{ write_fingerprints
    def write_fingerprints(self, opdata=None):
        fpath = os.path.expanduser(otr_basedir + '/' + otr_fingerprints)
        if chatServer:
            otr.otrl_privkey_write_fingerprints(
                chatServer._otr_userstate, fpath)
        else:
            print "chatServer not connected"
    #}}}
    #{{{ gone_secure
    def gone_secure(self, opdata=None, context=None):
        trust = context.active_fingerprint.trust
        if trust:
           trust = "V"
        else:
           trust = "U"
        
        buf = vimChatBeginChat(context.username)
        if buf:
            vimChatAppendStatusMessage( buf,"[OTR]",
                "-- " + trust + " OTR Connection Started")
            print trust+" OTR Connection Started with "+str(context.username)
    #}}}
    #{{{ gone_insecure
    def gone_insecure(self, opdata=None, context=None):
        buf = getBufByName(chats[context.username])
        if buf:
            vimChatAppendStatusMessage(buf,"[OTR]",
                "-- Secured OTR Connection Ended")
            print "Secure OTR Connection Ended with " + context.username
    #}}}
    #{{{ still_secure
    def still_secure(self, opdata=None, context=None, is_reply=0):
        # this is called when the OTR session was refreshed
        # (ie. new session keys have been created)
        # is_reply will be 0 when we started we started that refresh, 
        #   1 when the contact started it
        
        buf = getBufByName(chats[context.username])
        if buf:
            jid = "[OTR]"
            vimChatAppendStatusMessage(buf,"[OTR]",
                "-- Secured OTR Connection Refreshed")
            print "Secure OTR Connection Refreshed with "+str(context.username)
    #}}}
    #{{{ log_message
    def log_message(self, opdata=None, message=None):
        # log message to a logfile or something
        pass
    #}}}
    #{{{ max_message_size
    def max_message_size(self, opdata=None, context=None):
        """ looks up the max_message_size for the relevant protocol """
        # return 0 when no limit is defined
        #return msg_size[context.protocol]
        return 0
    #}}}
    #{{{ account_name
    def account_name(
        self, opdata=None, account=None, context=None, protocol=None):

        #return find_account(accountname=account, protocol).name
        if chatServer:
            jid = chatServer._jid.split('/')[0]
            print "accountname: " + jid
            return jid
        else:
            print "Could not get account name"
    #}}}
#}}}
#{{{ class VimChat
class VimChat(threading.Thread):

    #{{{ class Variables
    _rosterFile = '/tmp/vimChatRoster'
    _roster = {}
    buddyListBuffer = None
    _otr = ""
    #}}} 

    #Init Stuff
    #{{{ __init__
    def __init__(self, jid, jabberClient, roster, callbacks):
        self._jid = jid
        self._jids = jid.split('/')[0]
        self._recievedMessage = callbacks['message']
        self._presenceCallback = callbacks['presence']
        self._roster = roster
        threading.Thread.__init__ ( self )
        self.jabber = jabberClient
        self._protocol = 'xmpp'
    #}}}
    #{{{ run
    def run(self):
        self.jabber.RegisterHandler('message',self.jabberMessageReceive)
        self.jabber.RegisterHandler('presence',self.jabberPresenceReceive)
        self.jabberPresenceUpdate()

        #Socket stuff
        RECV_BUF = 4096
        self.xmppS = self.jabber.Connection._sock
        socketlist = [self.xmppS]
        online = 1

        #set up otr
        self.otrSetup()

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
            type = str(msg.getType()).lower()
            jid = fromJid.split('/')[0]
            body = str(msg.getBody())

            if pyotr_enabled and type != "groupchat":
                #OTR Stuff
                #{{{ Check for verification stuff
                is_internal, message, tlvs = otr.otrl_message_receiving(
                    self._otr_userstate, (
                        OtrOps(),None),self._jids,self._protocol,jid, body)

                context = otr.otrl_context_find(
                    self._otr_userstate,jid,self._jids,self._protocol,1)[0]


                
                if otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP_ABORT) is not None:
                    self.otrAbortVerify(context)
                elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP1) is not None:
                    if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT1:
                        self.otrAbortVerify(context)
                    else:
                        #TODO: prompt user for secret
                        pass
                elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP1Q) is not None:
                    if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT1:
                        self.otrAbortVerify(context)
                    else:
                        #TODO: prompt user for secret with question
                        tlv = otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP1Q)
                        vimChatSMPRequestNotify(context.username,tlv.data)
                elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP2) is not None:
                    if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT2:
                        self.otrAbortVerify(context)
                    else:
                        context.smstate.nextExpected = otr.OTRL_SMP_EXPECT4
                elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP3) is not None:
                    if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT3:
                        self.otrAbortVerify(context)
                    else:
                        if context.smstate.sm_prog_state == \
                            otr.OTRL_SMP_PROG_SUCCEEDED:
                            self.otrSMPVerifySuccess(context)
                            print "Successfully verified " + context.username
                        else:
                            self.otrSMPVerifyFailed(context)
                            print "Failed to verify " + context.username
                elif otr.otrl_tlv_find(tlvs, otr.OTRL_TLV_SMP4) is not None:
                    if context.smstate.nextExpected != otr.OTRL_SMP_EXPECT4:
                        self.otrAbortVerify(context)    
                    else:
                        context.smstate.nextExpected = otr.OTRL_SMP_EXPECT1
                        if context.smstate.sm_prog_state == \
                            otr.OTRL_SMP_PROG_SUCCEEDED:
                            self.otrSMPVerifySuccess(context)
                            print "Successfully verified " + context.username
                        else:
                            self.otrSMPVerifyFailed(context)
                            print "Failed to verify " + context.username
                #}}}

                secure = False
                type = otr.otrl_proto_message_type(body)
                if type == otr.OTRL_MSGTYPE_DATA \
                    and type != otr.OTRL_MSGTYPE_NOTOTR \
                    and type != otr.OTRL_MSGTYPE_TAGGEDPLAINTEXT:

                    if context.active_fingerprint:
                        trust = context.active_fingerprint.trust
                        if trust:
                            secure = "V"
                        else:
                            secure = "U"

                if not is_internal:
                    self._recievedMessage(fromJid, message.strip(),secure)
            elif type == "groupchat":
                parts = fromJid.split('/')
                chatroom = parts[0]
                if len(parts) > 1:
                    user = parts[1]
                else:
                    user = "--"
                self._recievedMessage(user, body.strip(), False, chatroom)
            else:
                self._recievedMessage(fromJid,body.strip())
    #}}}
    #{{{ jabberPresenceReceive
    def jabberPresenceReceive(self, conn, msg):
        fromJid = msg.getFrom()
        type = str(msg.getType()).lower()
        show = msg.getShow()
        status = msg.getStatus()
        priority = msg.getPriority()

        if not show:
            if priority:
                show = 'online'
            else:
                show = 'offline'

        if type == "groupchat":
            parts = fromJid.split('/')
            chatroom = parts[0]
            user = ""
            if len(parts) > 1:
                user = parts[1]

            self._presenceCallback(
                str(chatroom), str(user), show,status,priority)
        else:
            self._presenceCallback(str(fromJid), fromJid,show,status,priority)
    #}}}

    #To Jabber Functions
    #{{{ jabberOnSendMessage
    def jabberOnSendMessage(self, tojid, msg):
        msg = msg.strip()
        if not pyotr_enabled:
            self.jabberSendMessage(tojid,msg)
            return 0

        #only if otr is enabled
        new_message = otr.otrl_message_sending(
            self._otr_userstate,(OtrOps(),None),
            self._jids,self._protocol,tojid,msg,None)
            
        context = otr.otrl_context_find(
            self._otr_userstate,tojid,self._jids,self._protocol,1)[0]

        #if context.msgstate == otr.OTRL_MSGSTATE_ENCRYPTED
        otr.otrl_message_fragment_and_send(
            (OtrOps(),None),context,new_message,otr.OTRL_FRAGMENT_SEND_ALL)
    #}}}
    #{{{ jabberSendMessage
    def jabberSendMessage(self, tojid, msg):
        msg = msg.strip()
        m = xmpp.protocol.Message(to=tojid,body=msg,typ='chat')
        self.jabber.send(m)
    #}}}
    #{{{ jabberSendGroupChatMessage
    def jabberSendGroupChatMessage(self, room, msg):
        msg = msg.strip()
        m = xmpp.protocol.Message(to=room,body=msg,typ='groupchat')
        self.jabber.send(m)
    #}}}
    #{{{ jabberJoinGroupChat
    def jabberJoinGroupChat(self, room, name):
        roomStr = room + '/' + name
        self.jabber.send(xmpp.Presence(to=roomStr))
    #}}}
    #{{{ jabberLeaveGroupChat
    def jabberLeaveGroupChat(self, room):
        self.jabber.send(xmpp.Presence(to=room,typ='unavailable'))
    #}}}
    #{{{ jabberPresenceUpdate
    def jabberPresenceUpdate(self, show='', status='', priority=5):
        m = xmpp.protocol.Presence(
            None,
            show=show,
            priority=priority,
            status=status)
        self._presence = m
        self.jabber.send(m)
    #}}}
    #{{{ jabberGetPresence
    def jabberGetPresence(self):
        show = self._presence.getShow()
        status = self._presence.getStatus()
        return [show,status]
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

    #OTR Functions
    #{{{ otrSetup
    def otrSetup(self):
        #Set Up OTR Stuff If Available
        if not pyotr_enabled:
            return 0

        self._otr_userstate = otr.otrl_userstate_create()

        keypath = os.path.expanduser(otr_basedir + '/' + otr_keyfile)

        #Make the otr directory
        basedir = os.path.expanduser(otr_basedir)
        if not os.path.exists(basedir):
            os.makedirs(basedir)

        if not os.path.isfile(keypath):
            #Create it if it doesn't exist
            file(keypath,'w')
            jid = self._jid.split('/')[0]

            print "Generating OTR private key (may take a while)...."
            otr.otrl_privkey_generate(
                self._otr_userstate, keypath, jid, self._protocol)
        else:
            pass
            if os.access(keypath, os.R_OK):
                try:
                    otr.otrl_privkey_read(self._otr_userstate,keypath)
                except:
                    pass


        fprintPath = os.path.expanduser(otr_basedir + '/' + otr_fingerprints)
        if not os.path.isfile(fprintPath):
            #Create it if it doesn't exist
            file(fprintPath,'w')
        else:
            if os.access(fprintPath, os.R_OK):
                try:
                    otr.otrl_privkey_read_fingerprints(
                        self._otr_userstate,fprintPath)
                except:
                    pass
    #}}}
    #{{{ otrDisconnectChat
    def otrDisconnectChat(self, jid):
        context = otr.otrl_context_find(
            self._otr_userstate,jid,self._jids,self._protocol,1)[0]

        if context.msgstate == otr.OTRL_MSGSTATE_ENCRYPTED:
            otr.otrl_message_disconnect(
                self._otr_userstate,(OtrOps(),None),
                self._jids,self._protocol,jid)
    #}}}
    #{{{ otrManualVerifyBuddy
    def otrManualVerifyBuddy(self, jid):
        self.otrSetTrust(jid,"manual")
        buf = vimChatBeginChat(jid)
        if buf:
            vimChatAppendStatusMessage( buf,"[OTR]","-- Verified Fingerprint of " + jid)
            print "Verified "+jid
    #}}}
    #{{{ otrSMPVerifyBuddy
    def otrSMPVerifyBuddy(self, jid, question, secret):
        context = otr.otrl_context_find(
            self._otr_userstate,jid,self._jids,self._protocol,1)[0]

        otr.otrl_message_initiate_smp_q(
            self._otr_userstate,(OtrOps(), None),context,question,secret)

        buf = vimChatBeginChat(jid)
        if buf:
            vimChatAppendMessage(
                buf,"-- Sent Question to "+ jid +" for verification.")
            print "Sent Question for verification to "+str(context.username)
    #}}}
    #{{{ otrSMPVerifySuccess
    def otrSMPVerifySuccess(self,context):
        jid = context.username
        self.otrSetTrust(jid,"smp") 
        buf = vimChatBeginChat(jid)
        if buf:
            vimChatAppendStatusMessage(buf,"[OTR]",
                "-- Secret answered! "+ jid +" is verified.")
            print jid + " Gave correct secret -- verified!"
    #}}}
    #{{{ otrSMPVerifyFailed
    def otrSMPVerifyFailed(self,context):
        jid = context.username
        self.otrSetTrust(jid,"") 
        buf = vimChatBeginChat(jid)
        if buf:
            vimChatAppendStatusMessage( buf,"[OTR]",
                "-- Secret response Failed! "+ jid + " is NOT verified.")
            print jid + " Failed to answer secret, NOT verified!"
    #}}}
    #{{{ otrSMPRespond
    def otrSMPRespond(self,jid,secret):
        context = otr.otrl_context_find(
            self._otr_userstate,jid,self._jids,self._protocol,1)[0]

        otr.otrl_message_respond_smp(
            self._otr_userstate,(OtrOps(),None),context,secret)
        buf = vimChatBeginChat(jid)
        if buf:
            vimChatAppendStatusMessage( buf,"[OTR]",
                "-- Sent Secret to "+ jid +"")
            print "Sent secret response to " + jid
    #}}}
    #{{{ otrGeneratePrivateKey
    def otrGeneratePrivateKey(self):
        keypath = os.path.expanduser(otr_basedir + '/' + otr_keyfile)
        jid = self._jid.split('/')[0]
        otr.otrl_privkey_generate(
            self._otr_userstate, keypath, jid, self._protocol)
    #}}}
    #{{{ otrAbortVerify
    def otrAbortVerify(self,context):
        otr.otrl_message_abort_smp(
            self._otr_userstate, (OtrOps(), None), context)
    #}}}
    #{{{ otrSetTrust
    def otrSetTrust(self, jid, trust):
        context = otr.otrl_context_find(
            self._otr_userstate,jid,self._jids,self._protocol,1)[0]
        otr.otrl_context_set_trust(context.active_fingerprint,trust)
    #}}}
    #{{{ otrIsChatEncrypted
    def otrIsChatEncrypted(self, jid):
        context = otr.otrl_context_find(
            chatServer._otr_userstate,jid,
            chatServer._jids,chatServer._protocol,1)[0]

        if context.msgstate == otr.OTRL_MSGSTATE_ENCRYPTED:
            return True
        else:
            return False
    #}}}
        
#}}}

#HELPER FUNCTIONS
#{{{ formatPresenceUpdateLine
def formatPresenceUpdateLine(fromJid,show, status):
    tstamp = getTimestamp()
    return tstamp + " -- " + str(fromJid) + " is " + str(show) + ": " + str(status)
#}}}
#{{{ getJidParts
def getJidParts(jid):
    jidParts = str(jid).split('/')
    jid = jidParts[0]
    user = jid.split('@')[0]

    #Get A Resource if exists
    if len(jidParts) > 1:
        resource = jidParts[1]
    else:
        resource = ''

    return [jid,user,resource]
#}}}
#{{{ getTimestamp
def getTimestamp():
    return strftime("[%H:%M]")
#}}}
#{{{ getBufByName
def getBufByName(name):
    for buf in vim.buffers:
        if buf.name and buf.name.split('/')[-1] == name:
            return buf
    return None
#}}}
#{{{ moveCursorToBufBottom
def moveCursorToBufBottom(buf):
    # Update the cursor.
    for w in vim.windows:
        if w.buffer == buf:
            w.cursor = (len(buf), 0)
#}}}
#{{{ isGroupChat
def isGroupChat():
    try:
        groupchat = int(vim.eval('b:groupchat'))
        if groupchat == 1:
            return True
    except:
        pass

    return False
#}}}

#BUDDY LIST
#{{{ vimChatToggleBuddyList
def vimChatToggleBuddyList():
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
        vim.command("setlocal nomodifiable")
        vim.command("setlocal buftype=nowrite")
    except:
        vim.command("tabe " + rosterFile)


    commands = """
    setlocal foldtext=VimChatFoldText()
    set nowrap
    set foldmethod=marker
    nmap <buffer> <silent> <CR> :py vimChatBeginChatFromBuddyList()<CR>
    nnoremap <buffer> <silent> <Leader>l :py vimChatOpenLogFromBuddyList()<CR>
    nnoremap <buffer> B :py vimChatToggleBuddyList()<CR>
    nnoremap <buffer> q :py vimChatToggleBuddyList()<CR>
    nnoremap <buffer> <silent> <Leader>gc :py vimChatOpenGroupChat()<CR>
    nnoremap <buffer> <silent> <Leader>ss :py vimChatSetStatus()<CR>
    """
    vim.command(commands)

    chatServer.buddyListBuffer = vim.current.buffer
#}}}
#{{{ vimChatGetBuddyListItem
def vimChatGetBuddyListItem(item):
    if item == 'jid':
        vim.command("normal zo")
        vim.command("normal [z")
        vim.command("normal j")

        toJid = vim.current.line
        toJid = toJid.strip()
        return toJid
#}}}
#{{{ vimChatBeginChatFromBuddyList
def vimChatBeginChatFromBuddyList():
    toJid = vimChatGetBuddyListItem('jid')
    [jid,user,resource] = getJidParts(toJid)

    buf = vimChatBeginChat(jid)
    if not buf:
        #print "Error getting buddy info: " + jid
        return 0


    vim.command('sbuffer ' + str(buf.number))
    vimChatToggleBuddyList()
    vim.command('wincmd K')
#}}}

#CHAT BUFFERS
#{{{ vimChatBeginChat
def vimChatBeginChat(toJid,groupChat = False):
    #Set the ChatFile
    if toJid in chats.keys():
        chatFile = chats[toJid]
    else:
        chatFile = toJid
        chats[toJid] = chatFile

    bExists = int(vim.eval('buflisted("' + chatFile + '")'))
    if bExists: 
        return getBufByName(chatFile)
    else:
        vim.command("split " + chatFile)
        #Only do this stuff if its a new buffer
        if groupChat:
            vim.command('let b:groupchat=1')
        else:
            vim.command('let b:groupchat=0')

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
    nnoremap <buffer> <silent> i :py vimChatSendBufferShow()<CR>
    nnoremap <buffer> <silent> o :py vimChatSendBufferShow()<CR>
    nnoremap <buffer> <silent> a :py vimChatSendBufferShow()<CR>
    nnoremap <buffer> <silent> B :py vimChatToggleBuddyList()<CR>
    nnoremap <buffer> <silent> q :py vimChatDeleteChat()<CR>
    nnoremap <buffer> <silent> <Leader>l :py vimChatOpenLogFromChat()<CR>
    nnoremap <buffer> <silent> <Leader>ov :py vimChatOtrVerifyBuddy()<CR>
    nnoremap <buffer> <silent> <Leader>or :py vimChatOtrSMPRespond()<CR>
    """
    #au BufLeave <buffer> call clearmatches()
    vim.command(commands)
#}}}
#{{{ vimChatSendBufferShow
def vimChatSendBufferShow():
    toJid = vim.eval('b:buddyId')
    groupChat = vim.eval('b:groupchat')

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
    vim.command('let b:groupchat=' + str(groupChat))

#}}}
#{{{ vimChatAppendMessage
def vimChatAppendMessage(buf, message, showJid='Me',secure=False):
    if not buf:
        print "VimChat: Invalid Buffer to append to!"
        return 0

    lines = message.split("\n")
    tstamp = getTimestamp()

    jid,user,resource = getJidParts(showJid)
    logJid = buf.name.split('/')[-1]
    
    secureString = ""
    if secure:
        secureString = "(*" + secure + "*)"

    #Get the first line
    if resource:
        line = tstamp + secureString + \
            user + "/" + resource + ": " + lines.pop(0);
    else:
        line = tstamp + secureString + user + ": " + lines.pop(0);

    buf.append(line)
    if not secure or pyotr_logging:
        vimChatLog(logJid, line)

    for line in lines:
        line = '\t' + line
        buf.append(line)
        #if message is not secure, or if otr logging is on
        if not secure or pyotr_logging:
            vimChatLog(logJid, line)

    #move cursor to bottom of buffer
    moveCursorToBufBottom(buf)
#}}}
#{{{ vimChatAppendStatusMessage
def vimChatAppendStatusMessage(buf, prefix, message):
    if not buf:
        print "VimChat: Invalid Buffer to append to!"
        return 0
    
    jid = buf.name.split('/')[-1]
    jid,user,resource = getJidParts(jid)

    lines = message.split("\n")
    tstamp = getTimestamp()

    #Get the first line
    line = tstamp + prefix + ": " + lines.pop(0);

    buf.append(line)
    vimChatLog(jid, line)

    for line in lines:
        line = '\t' + line
        buf.append(line)
        vimChatLog(jid, line)

    #move cursor to bottom of buffer
    #moveCursorToBufBottom(buf)
#}}}
#{{{ vimChatDeleteChat
def vimChatDeleteChat():
    #remove it from chats list
    jid = vim.eval('b:buddyId')

    if pyotr_enabled:
        chatServer.otrDisconnectChat(jid)

    del chats[vim.current.buffer.name.split('/')[-1]]

    #Check if it was a groupchat
    if isGroupChat():
        chatServer.jabberLeaveGroupChat(jid)
    vim.command('bdelete!')
#}}}
#{{{ vimChatOpenGroupChat
def vimChatOpenGroupChat():
    chatroom = vim.eval('input("Chat Room to join: ")')
    name = vim.eval('input("Name to Use: ")')
    buf = vimChatBeginChat(chatroom, True)
    vim.command('sbuffer ' + str(buf.number))
    vimChatToggleBuddyList()
    vim.command('wincmd K')

    chatServer.jabberJoinGroupChat(chatroom, name)
#}}}

#NOTIFY
#{{{ vimChatNotify
def vimChatNotify(title, msg, type):
    #Do this so we can work without pynotify
    if pynotify_enabled:
        pynotify.init('vimchat')
        n = pynotify.Notification(title, msg, type)
        n.set_timeout(10000)
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
#{{{ vimChatOpenLogFromBuddyList
def vimChatOpenLogFromBuddyList():
    jid = vimChatGetBuddyListItem('jid')
    vimChatOpenLog(jid)
#}}}
#{{{ vimChatOpenLogFromChat
def vimChatOpenLogFromChat():
    jid = vim.eval('b:buddyId')
    if jid != '':
        vimChatOpenLog(jid)
    else:
        print "Invalid chat window!"
#}}}
#{{{ vimChatOpenLog
def vimChatOpenLog(jid):
        logPath = vim.eval('g:vimchat_logpath')
        logDir = os.path.expanduser(logPath + '/' + jid)
        if not os.path.exists(logDir):
            print "No Logfile Found"
            return 0
        else:
            print "Opening log for: " + logDir
            vim.command('tabe ' + logDir)
#}}}

#OUTGOING
#{{{ vimChatSendMessage
def vimChatSendMessage():
    try:
        toJid = vim.eval('b:buddyId')
    except:
        print "No valid chat found!"
        return 0

    chatBuf = getBufByName(chats[toJid])
    if not chatBuf:
        print "Chat Buffer Could not be found!"
        return 0

    r = vim.current.range
    body = ""
    for line in r:
        body = body + line + '\n'

    body = body.strip()

    global chatServer
    if isGroupChat():
        chatServer.jabberSendGroupChatMessage(toJid, body)
    else:
        chatServer.jabberOnSendMessage(toJid, body)
    
    secure = False

    if pyotr_enabled:
        secure = chatServer.otrIsChatEncrypted(toJid)
        if secure:
            secure = "e"

    if not isGroupChat():
        vimChatAppendMessage(chatBuf,body,'Me',secure)


    vim.command('hide')
    vim.command('sbuffer ' + str(chatBuf.number))
    vim.command('normal G')
#}}}
#{{{ vimChatSetStatus
def vimChatSetStatus():
    showStr = "(away,xa,dnd,chat)"
    show = vim.eval('input("Status(away,xa,dnd,chat): ")')
    status = vim.eval('input("Message: ")')
    priority = vim.eval('input("Priority: ")')
    chatServer.jabberPresenceUpdate(show,status,priority)
    print "Updated states to: " + priority + " -- " + show + " -- " + status
#}}}
#{{{ vimChatShowStatus
def vimChatShowStatus():
    print chatServer.jabberGetPresence()
#}}}
#{{{ vimChatSignOn
def vimChatSignOn():
    global chatServer
    vim.command('nnoremap <buffer> B :py vimChatToggleBuddyList()<CR>')

    vim.command('let s:hasVars = VimChatCheckVars()')
    hasVars = int(vim.eval('s:hasVars'))

    if hasVars < 1:
        print "Could not start VimChat!"
        return 0

    if chatServer:
        print "Already connected!"
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


    #Check if otr is enabled
    global pyotr_enabled
    global pyotr_logging

    enable_otr = int(vim.eval('g:vimchat_otr'))
    if enable_otr == 0:
        pyotr_enabled = False

    log_otr = int(vim.eval('g:vimchat_logotr'))
    if log_otr == 0:
        pyotr_logging = False

    chatServer = VimChat(jid, jabberClient, roster, callbacks)
    chatServer.start()

    print "Connected with VimChat (" + jid + ")"

    vimChatToggleBuddyList()
    
#}}}
#{{{ vimChatSignOff
def vimChatSignOff():
    global chatServer
    if chatServer:
        try:
            chatServer.disconnect()
            print "Signed Off VimChat!"
            chatServer = ""
        except Exception, e:
            print "Error signing off VimChat!"
            print e
    else:
        print "Not Connected!"
#}}}

#INCOMING
#{{{ vimChatPresenceUpdate
def vimChatPresenceUpdate(chat, fromJid, show, status, priority):
    #Only care if we have the chat window open
    fullJid = fromJid
    [fromJid,user,resource] = getJidParts(fromJid)
    [chat,nada,nada2] = getJidParts(fromJid)

    if chat in chats.keys():
        #Make sure buffer exists
        chatBuf = getBufByName(chats[chat])
        chatFile = chats[fromJid]
        bExists = int(vim.eval('buflisted("' + chatFile + '")'))
        if chatBuf and bExists:
            statusUpdateLine = formatPresenceUpdateLine(fullJid,show,status)
            if chatBuf[-1] != statusUpdateLine:
                chatBuf.append(statusUpdateLine)
                moveCursorToBufBottom(chatBuf)

                print "Presence Updated for: " + str(fullJid)
        else:
            #Should never get here!
            print "Buffer did not exist for: " + fromJid

#}}}
#{{{ vimChatMessageReceived
def vimChatMessageReceived(fromJid, message, secure=False, groupChat=""):
    #Store the buffer we were in
    origBufNum = vim.current.buffer.number

    # If the current buffer is the buddy list, then switch to a different
    # window first. This should help keep all the new windows split
    # horizontally.
    if origBufNum == chatServer.buddyListBuffer.number:
        vim.command('wincmd w')

    #Get Jid Parts
    [jid,user,resource] = getJidParts(fromJid)

    if groupChat == "":
        buf = vimChatBeginChat(jid)
        # Append message to the buffer.
        vimChatAppendMessage(buf, message, fromJid, secure)
    else:
        buf = vimChatBeginChat(groupChat)
        # Append message to the buffer.
        vimChatAppendMessage(buf, message, fromJid, secure)


    # Highlight the line.
    # TODO: This only works if the right window has focus.  Otherwise it
    # highlights the wrong lines.
    # vim.command("call matchadd('Error', '\%' . line('$') . 'l')")

    # Notify
    print "Message Received from: " + jid
    vimChatNotify(user + ' says:', message, 'dialog-warning')
#}}}

#OTR
#{{{ vimChatOtrVerifyBuddy
def vimChatOtrVerifyBuddy():
    if not pyotr_enabled:
        return 0

    jid = vim.eval('b:buddyId')
    response = str(vim.eval('input("Verify ' + jid + \
        ' (1:manual, 2:Question/Answer): ")'))
    if response == "1":
        response2 = str(vim.eval("input('Verify buddy? (y/n): ')")).lower()
        if response2 == "y":
            chatServer.otrManualVerifyBuddy(jid)
        else:
            print "Verify Aborted."
    elif response == "2":
        question = vim.eval('input("Enter Your Question: ")')
        secret = vim.eval('inputsecret("Enter your secret answer: ")')
        chatServer.otrSMPVerifyBuddy(jid,question,secret)
    else:
        print "Invalid Response."
#}}}
#{{{ vimChatOtrGenerateKey
def vimChatOtrGenerateKey():
    if not pyotr_enabled:
        return 0

    prompt = """Generate OTR key now (can take a while)? (y/n): """

    response = str(vim.eval("input('"+prompt+"')")).lower()
    if response == "y":
        print "Generating Key (please bear with us)..."
        chatServer.otrGeneratePrivateKey()
        print "Generated OTR Key!"
    else:
        print "Not Generating Key Now."
#}}}
#{{{ vimChatOtrSMPRequestNotify
def vimChatOtrSMPRequestNotify(jid, question):
    if not pyotr_enabled:
        return 0

    buf = vimChatBeginChat(jid)
    if buf:
        message = "-- OTR Verification Request received!  " + \
            "Press <Leader>or to answer the question below:\n" + question
        vimChatAppendMessage(buf,message, "[OTR]")
        print "OTR Verification Request from " + jid
#}}}
#{{{ vimChatSMPRespond
def vimChatSMPRespond():
    if not pyotr_enabled:
        return 0

    jid = vim.eval('b:buddyId')
    response = str(vim.eval(
            "inputsecret('Answer to "+ jid +": ')")).lower() 
    chatServer.otrSMPRespond(jid, response) 
#}}}

EOF
" vim:et:fdm=marker:sts=4:sw=4:ts=4
