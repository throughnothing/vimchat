syn match vimChatMsg 	/^.*:/				contains=vimChatTime,vimChatMe
syn match vimChatTime  	/\[\d\d:\d\d\]/		contained nextgroup=vimChatMe
syn match vimChatMe  	/Me:/		 		contained

hi link vimChatMsg Comment
hi link vimChatTime	Type
hi link vimChatMe	Statement
