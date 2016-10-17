# vim-flow-outline

Outline view for a JS module based on CtrlP and FlowType

![screencast][screencast]

## Installation

If you use [vim-plug][]:

    Plug 'ctrlpvim/ctrlp.vim'
    Plug 'andreypopp/vim-flow', { 'branch': 'expose-client-call' }
    Plug 'andreypopp/vim-flow-outline'

Then add a mapping:

    au FileType javascript nnoremap <C-n> <Esc>:FlowOutline<CR>

[vim-plug]: https://github.com/junegunn/vim-plug
[screencast]: ./screencast.gif
