let s:fzf_loaded = exists('g:fzf#vim#default_layout')
let s:ctrlp_loaded = exists('g:loaded_ctrlp')

if !s:ctrlp_loaded && !s:fzf_loaded
  finish
endif

if s:fzf_loaded

  " ------------------------------------------------------------------
  " FZF harness
  " ------------------------------------------------------------------

  let s:TYPE = {'dict': type({}), 'funcref': type(function('call'))}

  function! s:get_color(attr, ...)
    for group in a:000
      let code = synIDattr(synIDtrans(hlID(group)), a:attr, 'cterm')
      if code =~ '^[0-9]\+$'
        return code
      endif
    endfor
    return ''
  endfunction

  function! s:defaults()
    let rules = copy(get(g:, 'fzf_colors', {}))
    let colors = join(map(items(filter(map(rules, 'call("s:get_color", v:val)'), '!empty(v:val)')), 'join(v:val, ":")'), ',')
    return empty(colors) ? '' : ('--color='.colors)
  endfunction

  function! s:wrap(name, opts, bang)
    " fzf#wrap does not append --expect if sink or sink* is found
    let opts = copy(a:opts)
    if get(opts, 'options', '') !~ '--expect' && has_key(opts, 'sink*')
      let Sink = remove(opts, 'sink*')
      let wrapped = fzf#wrap(a:name, opts, a:bang)
      let wrapped['sink*'] = Sink
    else
      let wrapped = fzf#wrap(a:name, opts, a:bang)
    endif
    return wrapped
  endfunction

  function! s:fzf(name, opts, extra)
    let [extra, bang] = [{}, 0]
    if len(a:extra) <= 1
      let first = get(a:extra, 0, 0)
      if type(first) == s:TYPE.dict
        let extra = first
      else
        let bang = first
      endif
    elseif len(a:extra) == 2
      let [extra, bang] = a:extra
    else
      throw 'invalid number of arguments'
    endif

    let eopts  = has_key(extra, 'options') ? remove(extra, 'options') : ''
    let merged = extend(copy(a:opts), extra)
    let merged.options = join(filter([s:defaults(), get(merged, 'options', ''), eopts], '!empty(v:val)'))
    return fzf#run(s:wrap(a:name, merged, bang))
  endfunction
endif

python << EOF
import collections
import re

vim_flow_outline_item = collections.namedtuple('vim_flow_outline_item', [
  'line', 'loc', 'prefix', 'kind'
])

vim_flow_outline_find_loc = re.compile(r'\((\d+):(\d+)\)$')

def vim_flow_outline_process(node):

  def add(kind, loc, prefix, *line):
    outline.append(vim_flow_outline_item(list(line), loc, prefix, kind))

  def process(node, prefix=[]):
    if node['type'] == 'ImportDeclaration':
      kind = 'import type' if node['importKind'] == 'type' else 'import'
      for spec in node['specifiers']:
        if spec['type'] == 'ImportDefaultSpecifier':
          name = '%s from ...' % spec['local']['name']
          add('import', spec['loc'], prefix, kind, name)
        elif spec['type'] == 'ImportSpecifier':
          name = '{%s} from ...' % spec['local']['name']
          add('import', spec['loc'], prefix, kind, name)
    elif node['type'] == 'TypeAlias':
      add('type alias', node['loc'], prefix, 'type', node['id']['name'])
    elif node['type'] == 'ClassDeclaration':
      kind = 'class'
      name = node['id']['name']
      add('class', node['loc'], prefix, 'class', name + ' {...}')
      for item in node['body']['body']:
        process(item, prefix=prefix + ['class', name])
    elif node['type'] == 'MethodDefinition':
      name = node['key']['name'] + '(...)'
      if node['static']:
        name = 'static ' + name
      add('method', node['key']['loc'], prefix, name)
    elif node['type'] == 'FunctionDeclaration':
      if 'name' in node['id']:
        add('function', node['loc'], prefix, 'function', node['id']['name'] + '(...)')
    elif node['type'] == 'VariableDeclaration':
      for dec in node['declarations']:
        if 'name' in dec['id']:
          add('binding', node['loc'], prefix, node['kind'], dec['id']['name'] + ' = ...')
    elif node['type'] == 'ExportNamedDeclaration':
      if node['declaration']:
        process(node['declaration'], prefix=prefix + ['export'])

  outline = []

  for item in node['body']:
    process(item)

  return outline

def vim_flow_outline_fortmat_loc(loc):
  return '(%d:%d)' % (
    loc['start']['line'],
    loc['start']['column'] + 1)

EOF

let s:flow_from = '--from vim'

" Call wrapper for flow.
" Borrowed from flowtype/vim-flow.
function! <SID>FlowClientCall(cmd, suffix)
  " Invoke typechecker.
  " We also concatenate with the empty string because otherwise
  " cgetexpr complains about not having a String argument, even though
  " type(flow_result) == 1.
  let command = g:flow#flowpath.' '.a:cmd.' '.s:flow_from.' '.a:suffix

  let flow_result = system(command)

  " Handle the server still initializing
  if v:shell_error == 1
    echohl WarningMsg
    echomsg 'Flow server is still initializing...'
    echohl None
    cclose
    return 0
  endif

  " Handle timeout
  if v:shell_error == 3
    echohl WarningMsg
    echomsg 'Flow timed out, please try again!'
    echohl None
    cclose
    return 0
  endif

  return flow_result
endfunction

function! flow_outline#get_outline(filename)
  let l:outline = []
  let l:winwidth = winwidth(0)
  let l:res = <SID>FlowClientCall('ast ' . a:filename, '2> /dev/null')
python << EOF
import vim
import json

width = int(vim.eval('winwidth'), 10)
node = json.loads(vim.eval('res'))

for item in vim_flow_outline_process(node):
  line = ' '.join(item.prefix + item.line)
  loc = vim_flow_outline_fortmat_loc(item.loc)
  space = ''.join(' ' for s in range(width - len(line) - len(loc) - 4))
  vim.command("call add(l:outline, '%s%s%s')" % (line, space, loc))

EOF
  return l:outline
endfunction

function! flow_outline#accept(value)
python << EOF
import vim
import re
value = vim.eval('a:value')
match = vim_flow_outline_find_loc.search(value)
if match is not None:
  [line, column] = match.groups()
  vim.command('normal %sG%s|' % (line, column))
  vim.command('normal zz')
EOF
endfunction

if s:ctrlp_loaded

  function! flow_outline#ctrlp_accept(mode, value)
    call ctrlp#exit()
    call flow_outline#accept(a:value)
  endfunction

  function! flow_outline#ctrlp_id()
    retu s:id
  endfunction

  "" CtrlP outline
  cal add(g:ctrlp_ext_vars, {
    \ 'init': 'flow_outline#get_outline(s:crfile)',
    \ 'accept': 'flow_outline#accept',
    \ 'lname': 'outline',
    \ 'sname': 'ml',
    \ 'type': 'tabs',
    \ 'sort': 0,
    \ 'nolim': 1,
    \ })

  let s:id = g:ctrlp_builtins + len(g:ctrlp_ext_vars)

elseif s:fzf_loaded

  function! flow_outline#fzf_accept(value)
    call flow_outline#accept(a:value)
  endfunction

endif

function! flow_outline#Outline(...)
  if s:ctrlp_loaded
    call ctrlp#init(flow_outline#ctrlp_id())
  elseif s:fzf_loaded
    let l:outline = flow_outline#get_outline(bufname('%'))
    return s:fzf('fzf_merlin_outline', {
    \ 'source':  l:outline,
    \ 'sink':   function('g:flow_outline#fzf_accept'),
    \ 'options': '+m -x --tiebreak=index --header-lines=0 --ansi -d "\t" -n 2,1..2 --prompt="FlowOutline> "',
    \}, a:000)
  endif
endfunction

" Commands
command! FlowOutline call flow_outline#Outline()
