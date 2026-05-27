# ASMTris

Falling blocks game written purely in x86-64 Intel-syntax (AT&T 🤮) NASM assembly. Note that my *entire* legal argument and case to say that this is not T****s is based on some random comment I once read on Quora, so help me God.

This README **assumes** you know how to use a terminal and Linux! If you don't, good luck.

*This game was developed entirely by a human (i.e. me) without any AI help.*

## Overview

The idea behind all this was to get comfortable reading and writing x64 assembly for reversing and binary exploitation. After 26 days of development, I also ended up writing a ton of x64 notes so I could share everything I've learned with the world, which, surprisingly, turned out to be quite a lot.

I still have to think about how to format the massive amount of notes I've taken, but that'll come with time...

The game is not perfect, and I never intended it to be. It was a fun learning tool after all. It probably has a lot of bugs too, so feel free to fix them yourself (don't use AI though).

## Compatibility

The game is built for x86-64 (x64) Linux. It *might* run under MacOs or x86 Linux systems, but I have no idea. I haven't tested it, and I won't.

If you happen to test it under one of these conditions and the games **does work**, let me know! If the game doesn't and you want to fix it, feel free to open a PR ;).

## How to play

You can use the already built executable if you're in a trust-random-dude's-executable kind of mood, or you can build it yourself:

1. Install nasm (the compiler)
2. Clone the repo
3. `cd` to repo's dir
4. `make`

Once you have the executable, use `./asmtris` to run it.

### Game modes

The game has 29 levels and 4 game modes:

1. **Classic**. You can choose which level to start from. To advance to the next level, you need to clear a set number of lines. If you manage to beat level 29, you win
2. **Sprint**. Select a level and clear 40 lines as fast as possible
3. **Endless**. Drop speed increases every 10 lines. Standard game over applies
4. **Zen / Practice**. Select a level, and play. You can enable/disable game over. If disabled, lines are cleared instead of ending the game.

### Controls

These are also available in the in-game help panel:

- Left / Right arrows: move piece
- Up arrow: rotate piece
- Down arrow: soft drop
- Space: hard drop
- P: pause
- ESC: quit game

## Roadmap

- [X] Finish the game 🎉
- [ ] Finish x86-64 obsidian docs and upload it to blog
- [ ] Get cease-and-desist letter from Tetris
- [X] Do the dishes
- [ ] Add keylogger

## License

TL;DR: do what you want with it. If you copy-paste it and try to present it as your own, I will hunt you down for eternity...
