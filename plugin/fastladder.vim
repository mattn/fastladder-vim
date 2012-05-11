"=============================================================================
" File: fastladder.vim
" Author: Yasuhiro Matsumoto <mattn.jp@gmail.com>
" Last Change: 11-May-2012.
" Version: 1.0
" WebPage: http://github.com/mattn/fastladder-vim/tree/master
" Usage:
"
"   :FastLadder
"
" GetLatestVimScripts: 2683 1 :AutoInstall: fastladder.vim

let g:fastladder_vim_version = "0.9"
if &compatible
  finish
endif

if !exists('g:fastladder_server')
  let g:fastladder_server = 'http://fastladder.com'
endif

let s:SUBS_BUFNAME = '==FastLadder Subscribes=='
let s:LIST_BUFNAME = '==FastLadder Entries=='
let s:CONTENT_BUFNAME = '==FastLadder Content=='

function! s:wcwidth(ucs)
  let ucs = a:ucs
  if (ucs >= 0x1100
   \  && (ucs <= 0x115f
   \  || ucs == 0x2329
   \  || ucs == 0x232a
   \  || (ucs >= 0x2e80 && ucs <= 0xa4cf
   \      && ucs != 0x303f)
   \  || (ucs >= 0xac00 && ucs <= 0xd7a3)
   \  || (ucs >= 0xf900 && ucs <= 0xfaff)
   \  || (ucs >= 0xfe30 && ucs <= 0xfe6f)
   \  || (ucs >= 0xff00 && ucs <= 0xff60)
   \  || (ucs >= 0xffe0 && ucs <= 0xffe6)
   \  || (ucs >= 0x20000 && ucs <= 0x2fffd)
   \  || (ucs >= 0x30000 && ucs <= 0x3fffd)
   \  ))
    return 2
  endif
  return 1
endfunction

function! s:wcswidth(str)
  let mx_first = '^\(.\)'
  let str = a:str
  let width = 0
  while 1
    let ucs = char2nr(substitute(str, mx_first, '\1', ''))
    if ucs == 0
      break
    endif
    let width = width + s:wcwidth(ucs)
    let str = substitute(str, mx_first, '', '')
  endwhile
  return width
endfunction

function! s:truncate(str, num)
  let mx_first = '^\(.\)\(.*\)$'
  let str = a:str
  let ret = ''
  let width = 0
  while 1
    let char = substitute(str, mx_first, '\1', '')
    let ucs = char2nr(char)
    if ucs == 0
      break
    endif
    let cells = s:wcwidth(ucs)
    if width + cells > a:num
      break
    endif
    let width = width + cells
    let ret = ret . char
    let str = substitute(str, mx_first, '\2', '')
  endwhile
  while width + 1 <= a:num
    let ret = ret . " "
    let width = width + 1
  endwhile
  return ret
endfunction

function! s:nr2byte(nr)
  if a:nr < 0x80
    return nr2char(a:nr)
  elseif a:nr < 0x800
    return nr2char(a:nr/64+192).nr2char(a:nr%64+128)
  else
    return nr2char(a:nr/4096%16+224).nr2char(a:nr/64%64+128).nr2char(a:nr%64+128)
  endif
endfunction

function! s:nr2enc_char(charcode)
  if &encoding == 'utf-8'
    return nr2char(a:charcode)
  endif
  let char = s:nr2byte(a:charcode)
  if strlen(char) > 1
    let char = strtrans(iconv(char, 'utf-8', &encoding))
  endif
  return char
endfunction

function! s:nr2hex(nr)
  let n = a:nr
  let r = ""
  while n
    let r = '0123456789ABCDEF'[n % 16] . r
    let n = n / 16
  endwhile
  return r
endfunction

function! s:encodeURIComponent(instr)
  let instr = iconv(a:instr, &enc, "utf-8")
  let len = strlen(instr)
  let i = 0
  let outstr = ''
  while i < len
    let ch = instr[i]
    if ch =~# '[0-9A-Za-z-._~!''()*]'
      let outstr = outstr . ch
    elseif ch == ' '
      let outstr = outstr . '+'
    else
      let outstr = outstr . '%' . substitute('0' . s:nr2hex(char2nr(ch)), '^.*\(..\)$', '\1', '')
    endif
    let i = i + 1
  endwhile
  return outstr
endfunction

function! s:decodeEntityReference(str)
  let str = a:str
  let str = substitute(str, '&gt;', '>', 'g')
  let str = substitute(str, '&lt;', '<', 'g')
  let str = substitute(str, '&quot;', '"', 'g')
  let str = substitute(str, '&apos;', "'", 'g')
  let str = substitute(str, '&nbsp;', ' ', 'g')
  let str = substitute(str, '&yen;', '\&#65509;', 'g')
  let str = substitute(str, '&#\(\d\+\);', '\=s:nr2enc_char(submatch(1))', 'g')
  let str = substitute(str, '&amp;', '\&', 'g')
  return str
endfunction

function! s:item2query(items, sep)
  let ret = ''
  if type(a:items) == 4
    for key in keys(a:items)
      if strlen(ret) | let ret .= a:sep | endif
      let ret .= key . "=" . s:encodeURIComponent(a:items[key])
    endfor
  elseif type(a:items) == 3
    for item in a:items
      if strlen(ret) | let ret .= a:sep | endif
      let ret .= item
    endfor
  else
    let ret = a:items
  endif
  return ret
endfunction

function! s:SetPin(entry, pin)
  if a:pin
    let res = webapi#http#post(g:fastladder_server . "/api/pin/add", {"ApiKey": s:apikey, "link": a:entry['link'], "title": a:entry['title']}, {"Cookie" : join(s:cookies, '; ')})
  else
    let res = webapi#http#post(g:fastladder_server . "/api/pin/remove", {"ApiKey": s:apikey, "link": a:entry['link']}, {"Cookie": join(s:cookies, '; ')})
  endif
  return webapi#json#decode(res.content)['isSuccess']
endfunction

function! s:GetEntries(subscribe_id, unread)
  if a:unread
    let res = webapi#http#post(g:fastladder_server . "/api/unread", {"ApiKey": s:apikey, "subscribe_id": a:subscribe_id}, {"Cookie": join(s:cookies, '; ')})
  else
    let res = webapi#http#post(g:fastladder_server . "/api/all", {"ApiKey": s:apikey, "subscribe_id": a:subscribe_id}, {"Cookie": join(s:cookies, '; ')})
  endif
  return webapi#json#decode(res.content)['items']
endfunction

function! s:GetPins()
  let res = webapi#http#post(g:fastladder_server . "/api/pin/all", {"ApiKey": s:apikey}, {"Cookie": join(s:cookies, '; ')})
  return webapi#json#decode(res.content)
endfunction

function! s:GetSubsList(unread)
  let res = webapi#http#post(g:fastladder_server . "/api/subs", {"ApiKey": s:apikey, "unread": a:unread}, {"Cookie": join(s:cookies, '; ')})
  return webapi#json#decode(res.content)
endfunction

function! s:ShowEntry()
  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr > 0 && winnr != winnr()
    execute winnr.'wincmd w'
  endif

  let subscribe_row = b:subscribe_row
  let str = getline('.')
  let mx_row_mark = '^\(\d\+\)\(: \)\([* ]\)\(.*\)$'
  let row = str2nr(substitute(matchstr(str, mx_row_mark), mx_row_mark, '\1', '')) - 1

  let bufname = s:CONTENT_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    if bufname('%').'X' ==# 'X' && &modified == 0
      silent! edit `=bufname`
    else
      let height = winheight('.') * 7 / 10
      silent! exec 'belowright '.height.'new `=bufname`'
    endif
  else
    if winnr != winnr()
      execute winnr.'wincmd w'
    endif
  endif
  setlocal buftype=nofile bufhidden=hide noswapfile wrap ft= nonumber modifiable
  silent! %d _
  let entry = s:entries[row]

  call setline(1, printf("Source: %s", s:subslist[subscribe_row]['title']))
  call setline(2, printf("Title: %s", entry['title']))
  call setline(3, printf("URL: %s", entry['link']))
  call setline(4, printf("Publish: %s", strftime("%Y-%m-%dT%H:%M:%SZ", entry['created_on'])))
  call setline(5, printf("Author: %s", entry['author']))
  call setline(6, "---------------------------------------------")
  normal! G
  let body = entry['body']
  let body = substitute(body, "\n", "\r", 'g')
  let body = substitute(body, '^<!\[CDATA\[\(.*\)\]\]>$', '\1', 'g')
  let body = s:decodeEntityReference(body)
  let body = substitute(body, '\(<br[^>]*>\|<p[^>]*>\|</p[^>]*>\)', "\r", 'g')
  let body = substitute(body, '<[^>]\+>', '', 'g')
  let body = substitute(body, '^[\s\t\r\n]*', '', '')
  let body = s:decodeEntityReference(body)
  call setline(7, body)
  silent! %s/\r/\r/g
  setlocal nomodifiable
  syntax match SpecialKey /^\(Source\|Title\|URL\|Publish\|Author\):/he=e-1
  nnoremap <silent> <buffer> <space> <c-d>
  nnoremap <silent> <buffer> q :bw!<cr>
  exec 'nnoremap <silent> <buffer> <c-p> :call <SID>ShowPrevEntry()<cr>'
  exec 'nnoremap <silent> <buffer> <c-n> :call <SID>ShowNextEntry()<cr>'
  exec 'nnoremap <silent> <buffer> <c-i> :call <SID>ShowEntryInBrowser()<cr>'
  exec 'nnoremap <silent> <buffer> <c-t> :call <SID>ToggleReaded()<cr>'
  exec 'nnoremap <silent> <buffer> <s-s> :call <SID>ToggleStarred()<cr>'
  exec 'nnoremap <silent> <buffer> ?     :call <SID>Help()<cr>'
  let b:id = entry['id']
  let b:url = entry['link']
  normal! gg
endfunction

function! s:ShowEntryInBrowser()
  let bufname = s:CONTENT_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    return
  endif
  if winnr != winnr()
    execute winnr.'wincmd w'
  endif

  if has('win32')
    silent! exec "!start rundll32 url.dll,FileProtocolHandler ".escape(b:url ,'#')
  elseif has('mac')
    silent! exec "!open '".escape(b:url ,'#')."'"
  else
    call system("firefox '".b:url."' 2>&1 > /dev/null &")
  endif
  redraw!
endfunction

function! s:ShowPrevEntry()
  let bufname = s:CONTENT_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    return
  endif
  if winnr != winnr()
    execute winnr.'wincmd w'
  endif

  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr > 0 && winnr != winnr()
    execute winnr.'wincmd w'
    normal! k
    call s:ShowEntry()
  endif
endfunction

function! s:ShowNextEntry()
  let bufname = s:CONTENT_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    return
  endif
  if winnr != winnr()
    execute winnr.'wincmd w'
  endif

  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr > 0 && winnr != winnr()
    execute winnr.'wincmd w'
    normal! j
    call s:ShowEntry()
  endif
endfunction

function! s:TogglePin()
  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  let oldwinnr = winnr()
  if winnr > 0 && winnr != oldwinnr
    execute winnr.'wincmd w'
  endif

  let str = getline('.')
  let mx_row_mark = '^\(\d\+\)\(: \)\([* ]\)\(.*\)$'
  let row = str2nr(substitute(matchstr(str, mx_row_mark), mx_row_mark, '\1', '')) - 1
  let entry = s:entries[row]
  let pin = entry['pin'] ? 0 : 1
  if s:SetPin(entry, pin)
    let entry['pin'] = pin
    let str = substitute(matchstr(str, mx_row_mark), mx_row_mark, '\1\2'.(pin ? '*' : ' ').'\4', '')
    let oldmodifiable = &l:modifiable
    setlocal modifiable
    call setline(line('.'), str)
    let &l:modifiable = oldmodifiable
  endif
  if winnr > 0 && winnr != oldwinnr
    wincmd p
  endif
endfunction

function! s:TouchAll()
  if confirm("Area you sure?", "&Yes\n&No") != 1
    return
  endif
  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr() == winnr
    silent! bw!
  endif

  let bufname = s:SUBS_BUFNAME
  let winnr = bufwinnr(bufname)
  let oldwinnr = winnr()
  if winnr > 0 && winnr != oldwinnr
    execute winnr.'wincmd w'
  endif

  let str = getline('.')
  let mx_row = '^\(\d\+\): .*$'
  let row = str2nr(substitute(matchstr(str, mx_row), mx_row, '\1', '')) - 1

  let subscribe_id = s:subslist[row]['subscribe_id']
  let res = webapi#http#post(g:fastladder_server . "/api/touch_all", {"ApiKey": s:apikey, "subscribe_id": subscribe_id}, {"Cookie": "reader_sid=".s:apikey})
  normal r
  if winnr > 0 && winnr != oldwinnr
    wincmd p
  else
    normal r
  endif
  return webapi#json#decode(res.content)["isSuccess"]
endfunction

function! s:ShowEntries(unread)
  let bufname = s:SUBS_BUFNAME
  let winnr = bufnr(bufname)
  if winnr > 0 && winnr != winnr()
    execute winnr.'wincmd w'
  endif

  let str = getline('.')
  let mx_row = '^\(\d\+\): .*$'
  let row = str2nr(substitute(matchstr(str, mx_row), mx_row, '\1', '')) - 1

  let unread = a:unread
  if unread == -1
    if exists('b:unread')
      let unread = b:unread
    else
      let unread = 1
    endif
  endif
  let bufname = s:LIST_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    if &modified == 0
      silent! edit `=bufname`
    else
      silent! rightbelow new `=bufname`
    endif
  else
    if winnr != winnr()
      execute winnr.'wincmd w'
    endif
  endif
  setlocal buftype=nofile bufhidden=hide noswapfile nowrap ft= nowrap nonumber cursorline modifiable
  silent! %d _
  redraw!

  let b:unread = unread
  if row != -1
    let subscribe_id = s:subslist[row]['subscribe_id']
    let b:subscribe_id = subscribe_id
    let b:subscribe_row = row
    if unread
      echo "reading unread entries..."
    else
      echo "reading full entries..."
    endif
    silent! unlet s:entries
    let s:entries = s:GetEntries(subscribe_id, unread)
    let pins = {}
    for pin in s:pins
      let pins[pin['link']] = 1
    endfor
    let cnt = 1
    for l:entry in s:entries
      let source = s:truncate(s:subslist[row]['title'], 20)
      let flag = has_key(pins, l:entry['link'])
      let l:entry['pin'] = flag
      call setline(cnt, printf("%03d: %s %s %s", cnt, (flag ? "*" : " "), source, l:entry['title']))
      let cnt = cnt + 1
    endfor
  endif
  setlocal nomodifiable
  syntax match SpecialKey /^\d\+:/he=e-1
  exec 'nnoremap <silent> <buffer> <cr>  :call <SID>ShowEntry()<cr>'
  exec 'nnoremap <silent> <buffer> r     :call <SID>ShowEntries(-1)<cr>'
  exec 'nnoremap <silent> <buffer> <s-a> :call <SID>ShowEntries(0)<cr>'
  exec 'nnoremap <silent> <buffer> <c-a> :call <SID>ShowEntries(1)<cr>'
  exec 'nnoremap <silent> <buffer> <c-t> :call <SID>TouchAll()<cr>'
  exec 'nnoremap <silent> <buffer> *     :call <SID>TogglePin()<cr>'
  exec 'nnoremap <silent> <buffer> ?     :call <SID>Help()<cr>'
  nnoremap <silent> <buffer> <c-n> j
  nnoremap <silent> <buffer> <c-p> k
  nnoremap <silent> <buffer> q :bw!<cr>
  normal! gg
  redraw!
  echo ""
endfunction

function! s:ShowSubsList(unread)
  if exists("g:fastladder_user")
    let user = g:fastladder_user
  else
    let user = input('FastLadder user:')
  endif
  if exists("g:fastladder_passwd")
    let passwd = g:fastladder_passwd
  else
    let passwd = inputsecret('FastLadder password:')
  endif
    
  if len(user) == 0 || len(passwd) == 0
    echohl WarningMsg
    echo "authentication required for FastLadder."
    echohl None
    return
  end

  silent! unlet s:apikey
  if !exists("s:apikey")
    if g:fastladder_server =~ 'reader\.livedoor\.com'
	  let res = webapi#http#post("http://member.livedoor.com/login/index", {"livedoor_id": user, "password": passwd})
	  let cookies = res.header
      call filter(cookies, 'v:val =~ "^Set-Cookie: "')
      call map(cookies, "matchstr(v:val, '^Set-Cookie: \\zs[^;]\\+\\ze;.*')")
	  let res = webapi#http#post(g:fastladder_server . "/reader/", {"Cookie": join(cookies, '; ')})
      let s:apikey = matchstr(res.content, '.*reader_sid=\([^;]\+\).*')

      call filter(res.header, 'v:val =~ "^Set-Cookie: "')
      call map(res.header, "substitute(v:val, '^Set-Cookie: \\([^;]\\+\\);.*', '\\1', '')")
      call filter(res.header, 'v:val !~ "^reader_sid="')
      let s:cookies = add(cookies, 'reader_sid='.s:apikey)
    else
      let res = webapi#http#post(g:fastladder_server . "/login", {"username": user, "password": passwd}, {}, '', 0)
	  let g:hoge = deepcopy(res)
      call filter(res.header, 'v:val =~ "^Set-Cookie: "')
	  let g:hogehogehoge = deepcopy(res.header)
      let s:apikey = substitute(res.header[0], '.*reader_sid=\([^;]\+\).*', '\1', '')
      let s:cookies = ['reader_sid='.s:apikey]
    endif
  endif

  let unread = a:unread
  if unread == -1
    if exists('b:unread')
      let unread = b:unread
    else
      let unread = 1
    endif
  endif

  let bufname = s:SUBS_BUFNAME
  let winnr = bufwinnr(bufname)
  if winnr < 1
    if &modified == 0
      silent! edit `=bufname`
    else
      silent! belowright new `=bufname`
    endif
  else
    if winnr != winnr()
      execute winnr.'wincmd w'
    endif
  endif
  setlocal buftype=nofile bufhidden=hide noswapfile nowrap ft= nowrap nonumber cursorline modifiable
  silent! %d _
  redraw!

  if unread
    echo "reading unread subscribes..."
  else
    echo "reading full subscribes..."
  endif
  let b:unread = unread
  silent! unlet s:subslist
  let s:subslist = s:GetSubsList(unread)
  silent! unlet s:pins
  let s:pins = s:GetPins()
  let cnt = 1
  for l:subs in s:subslist
    call setline(cnt, printf("%03d: %s (%d)", cnt, l:subs['title'], l:subs['unread_count']))
    let cnt = cnt + 1
  endfor
  setlocal nomodifiable
  syntax match SpecialKey /^\d\+:/he=e-1
  exec 'nnoremap <silent> <buffer> <cr>  :call <SID>ShowEntries(-1)<cr>'
  exec 'nnoremap <silent> <buffer> r     :call <SID>ShowSubsList(-1)<cr>'
  exec 'nnoremap <silent> <buffer> <s-a> :call <SID>ShowSubsList(0)<cr>'
  exec 'nnoremap <silent> <buffer> <c-a> :call <SID>ShowSubsList(1)<cr>'
  exec 'nnoremap <silent> <buffer> <c-t> :call <SID>TouchAll()<cr>'
  exec 'nnoremap <silent> <buffer> ?     :call <SID>Help()<cr>'
  nnoremap <silent> <buffer> <c-n> j
  nnoremap <silent> <buffer> <c-p> k
  nnoremap <silent> <buffer> q :bw!<cr>
  normal! gg
  redraw!
  echo ""
endfunction

function! s:Help()
  echohl None
  echo 'FastLadder.vim version ' . g:fastladder_vim_version
  echohl Title
  echo '[LIST]'
  echohl SpecialKey
  echo '<c-n>     : goto next and open entry'
  echo '<c-p>     : goto prev and open entry'
  echo '<cr>      : show the entry'
  echo '<c-a>     : show all list'
  echo '<s-a>     : show unread list'
  echo '*         : toggle pin'
  echo 'r         : reload entries'
  echo 'q         : close window'
  echohl Title
  echo '[CONTENT]'
  echohl SpecialKey
  echo '<c-n>     : show next entry'
  echo '<c-p>     : show prev entry'
  echo '<c-i>     : open URL with browser'
  echo 'q         : close window'
  echohl MoreMsg
  echo "[Hit any key]"
  echohl None
  call getchar()
  redraw!
endfunction

function! s:FastLadder()
  call s:ShowSubsList(1)
endfunction

command! FastLadder call s:FastLadder()

" vim:set et
