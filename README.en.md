# LoLBoost

*[Português](README.md) · **English***

**From 90–120 fps, with sudden drops to 60, to 200 fps in League of Legends.**

On the same machine that ran AAA games at 4K max settings without stuttering. It wasn't a weak PC, it
wasn't missing hardware, and it wasn't a misconfigured Windows — **it was LoL**, plus two things that
were working against it.

**The machine this was measured on, so you can compare with yours:**

| | |
|---|---|
| **Processor** | AMD Ryzen 7 5700X (8 cores / 16 threads) |
| **Graphics card** | AMD Radeon RX 9070 XT |
| **Memory** | 32 GB (2×16 GB, DDR4-3200) |
| **Motherboard** | MSI MPG B550 Gaming Plus |
| **Playing at** | 1080p, settings on low |

In other words: **hardware far above what LoL needs** — and even so the game wouldn't go past 90–120
fps. That contrast is exactly what shows the problem wasn't a lack of PC.

> ### ⚠️ Read this before downloading: this may not be for you
>
> This is **not an "FPS optimizer"**. It fixes **one** specific problem: when your processor has one
> core packed full while the graphics card sits around doing nothing.
>
> If your PC **has no dedicated graphics card** — meaning it uses the video built into the processor —
> your limit is most likely the graphics, **not** the processor. In that case nothing here will give
> you 200 fps, and I'm not going to pretend it will.
>
> **[How to find out in 2 minutes which case you're in](#does-this-apply-to-me)** — that's worth more
> than anything else I write here.

---

## Contents

- [The problem, in 30 seconds](#the-problem-in-30-seconds)
- [**Does this apply to me?**](#does-this-apply-to-me)
- [The main finding: the graphics driver was on the game's core](#the-main-finding-the-graphics-driver-was-on-the-games-core)
- [The extra finding: the optimization program was getting in the way](#the-extra-finding-the-optimization-program-was-getting-in-the-way)
- [How to use it](#how-to-use-it)
- [What it changes on your machine](#what-it-changes-on-your-machine)
- [How much gain to expect](#how-much-gain-to-expect)
- [Can this get me banned?](#can-this-get-me-banned)
- [Cases where it holds back on purpose](#cases-where-it-holds-back-on-purpose)
- [Documentation and tests](#documentation-and-tests)

---

## The problem, in 30 seconds

A modern processor has several **cores** — think of each one as a worker. The more workers, the more
things your PC does at the same time.

The catch is that League **does almost all of its heavy work on a single core**. Riot has confirmed
this publicly. So it doesn't matter whether you have 8 or 16: the game leans on **one**, and when that
one fills up, your FPS drops — even with all the others sitting idle.

That's exactly what showed up while monitoring a real 29-minute match. The number on each core is how
busy it was:

```
#0:59%  #1:45%  #2:74%  #3:87%  #4:28%  #5:28%  #6:65%  #7:65%
#8:32%  #9:31%  #10:54% #11:53% #12:38% #13:37% #14:68%  #15:99%  ← THIS one, packed
```

**One core at 99% while the graphics card was at 10%.** The card had nothing to do: all the work was
piled onto a single worker.

This is why a heavy game at 4K runs smooth and LoL doesn't. In the heavy game, the graphics card does
the work. In LoL, **one** processor core does. They're **opposite** problems — and that confusion is
what dragged the diagnosis out for weeks.

It's also why lowering graphics settings didn't help: **the card was already idle.** It made the image
worse without giving back a single frame.

> **Being honest about what this monitoring proves:** it shows which **core** filled up, not which
> program filled it. That the load was League's is by far the most likely explanation — it was the only
> game open, and Riot confirms the game works that way — but that isn't the same as having measured it.
> Logged here as a well-founded assumption, not a proven fact.

---

## Does this apply to me?

Two minutes, and you don't have to install anything to find out:

1. Press `Ctrl` + `Shift` + `Esc` to open **Task Manager**
2. Go to the **Performance** tab
3. Get into a match and play until a **big late-game fight** (the heaviest moment in the game)
4. Go back to Task Manager and look at **CPU** and **GPU** at the same time

| What you see | What it means | Does this project help? |
|---|---|---|
| **GPU low** (10–40%) and on the processor **one core maxed out** while the others are relaxed | Exactly the problem this project fixes | **Yes** |
| **GPU at 95–100%** | Your limit is the graphics card, not the processor | **No.** Lowering resolution and graphics quality is what will give you FPS. Start there |
| Processor and graphics both relaxed, and FPS stuck at a round number (60, 120, 144) | Probably a frame limiter, or your monitor's refresh rate | **No.** Check that first — it's free and fixes it immediately |

> **To see core by core:** right-click the CPU graph → *Change graph to* → *Logical processors*.
> Instead of one graph you get a grid of small squares — one per core. That's where the packed core
> becomes obvious.

---

## The main finding: the graphics driver was on the game's core

Here's the part almost nobody tells you: **the graphics card also gives work to the processor.** It's
not the card working alone — every frame it draws goes through a piece of the driver, and that piece
runs on the processor. And it has to run on **some** core.

By default, Windows doesn't coordinate that with anything. It puts the driver's work wherever it lands
— and here it was landing **exactly on the core the game was already filling up.** Two tenants in the
one crowded room, while seven rooms sat empty.

Worse: when I measured all 16 cores one by one, the core the driver was on was the **worst on the
machine** during the stutter moments — nearly 3× worse than the best one.

**Getting the driver out of there is what locked in the 200 fps.** Not "200 average, fluctuating":
200 steady.

And that's why this script **measures** instead of telling you to copy a number: which core is free
and which one is in the way **changes from PC to PC**. Copying the setup that worked on my machine
could put your driver on the worst core of your processor.

> This isn't a hack or a trick: it's an option Windows itself provides to say which core a device's
> work should run on. It exists precisely for cases like this. What Windows doesn't do is **figure out
> on its own** which core is best — and nobody had ever told it.

---

## The extra finding: the optimization program was getting in the way

This part only matters to you **if you use some optimizer** that touches program priority. If you
don't, **feel free to skip it** — the main finding is the one above, and it doesn't depend on this.

**Process Lasso** is a popular Windows optimization program — it shows up in practically every "how to
gain FPS" guide. It controls how much attention Windows gives each program.

It has a feature enabled out of the box called **ProBalance**, which does the following: when a program
starts eating a lot of processor, ProBalance **lowers its priority** so the rest of Windows stays
responsive.

Good intentions. The problem is obvious once someone points it out:

> **A game eats a lot of processor by nature. So ProBalance was lowering the game's priority.**

The program installed to make the game run faster was making it run slower. And it wasn't subtle —
you could see it in its own window, the word **"Restrained"** right next to League of Legends.

Worse: setting the game's priority to "High" **doesn't fix it**. ProBalance pulls it back down. You
have to explicitly tell it "leave this program alone".

**None of the guides I checked warn about this.** Not even
[valleyofdoom's PC-Tuning](https://github.com/valleyofdoom/PC-Tuning), which is the reference in this
space — it doesn't mention League of Legends, Process Lasso or ProBalance anywhere.

Worth logging the size of this honestly: **releasing that brake raised the average**, but what made
the FPS **steady** was the main finding, the driver one. They're two different problems, and most
people only have the second.

> **If you don't use Process Lasso, none of this is happening to you** — and the script installs and
> configures the program properly, without creating the problem. The main finding applies to you in
> full.

---

## How to use it

### Before you start

- **Windows 10 or 11**
- **An administrator account** on the PC (the script asks for Windows' confirmation)
- **About 15 minutes**, 10 of which are just the script measuring on its own
- **League of Legends and Riot Client closed.** If the game is open it undoes the config file edit when
  it closes — the script detects this and tells you

### 1. Close the game for real

Check the tray next to the clock to make sure nothing from Riot is still running.

### 2. Open PowerShell as administrator

Start menu → type `powershell` → right-click → **Run as administrator** → **Yes** on Windows'
confirmation dialog.

### 3. Paste one command

This downloads and runs it. You don't need anything else installed:

```powershell
irm https://github.com/gaamororais/lol-optimizer/archive/refs/heads/main.zip -OutFile "$env:TEMP\lolboost.zip"; Expand-Archive "$env:TEMP\lolboost.zip" "$env:LOCALAPPDATA" -Force; & "$env:LOCALAPPDATA\lol-optimizer-main\LoLBoost\LoLBoost.bat"
```

**Prefer clicking to pasting a command?** Green **`Code`** button above → **`Download ZIP`** → extract
→ open the `LoLBoost` folder → right-click **`LoLBoost.bat`** → **Run as administrator**.

The files land in a folder under your user account, and the undo script is generated right there. To
run it again later, use the same command.

### 4. It asks, you answer

Six stages. It **asks before anything non-trivial**, and you can answer **N** (no) to any of them — the
rest continues. **The prompts are in Portuguese, and `S` means yes.**

| Stage | What happens |
|---|---|
| **1** | Checks what hardware you have, and asks whether your graphics card is dedicated or built into the processor |
| **2** | Simple, reversible tweaks: turns off Windows background screen recording, sets the power plan to High Performance, and adjusts the game's config file |
| **3** | **Measures your cores, one by one**, to find the best one for the graphics driver. This is the 10-minute part |
| **4** | Puts the graphics driver on the core that won **in your measurement** |
| **5** | Configures Process Lasso: High priority for the game, and "leave this one alone" in ProBalance |
| **6** | Writes `DESFAZER.ps1` (the undo script), which reverts everything |

> ### ⚠️ In stage 3 the screen will flicker, and may go black for a few seconds
>
> That's expected — to measure each core, the graphics driver gets restarted. It happens once per core.
> **Don't touch the PC during that part.**
>
> There's a small risk the driver hangs instead of coming back. If that happens, **reboot with the
> power button** and run it again. If you'd rather not take that risk, **answer N to this stage** —
> stage 5, which is where most of the gain is, works without it.

### 5. Restart the PC

Required. The graphics driver change only takes effect after a restart.

### 6. After restarting, check 3 things

1. **Is Process Lasso open?** It has to be running for any of it to apply. If your FPS ever drops out
   of nowhere, that's the first thing to look at.
2. **Is your monitor at its maximum refresh rate?** Settings → System → Display → Advanced display.
   Having a 144 or 240 Hz monitor while Windows sits at 60 throws all of this away.
3. **In the Riot Client**, under the gear icon: on match start, pick **"Close client window"**. The
   client keeps eating processor behind the game if it stays open.

### If you want to undo it

**There's a shortcut on your Desktop called `DESFAZER LoLBoost`** (*desfazer* = undo). Double-click
it, accept Windows' confirmation, and it reverts everything. Then restart the PC.

It's created **along with the first change**, not at the end — so even if the script stops halfway for
any reason, the shortcut is already there and already covers whatever was touched up to that point.
And it deletes itself after reverting, so it doesn't leave junk on your Desktop.

The actual file is `DESFAZER.ps1`, in the same folder as the script, if you'd rather run it from
there.

It undoes everything the script changed. The only thing it does **not** do is uninstall Process Lasso,
if the script installed it for you — you remove that from Settings → Apps, like any other program.

---

## What it changes on your machine

No fine print. Everything here is reversible through `DESFAZER.ps1`:

| What it changes | Why |
|---|---|
| Turns off Windows **background screen recording** (GameDVR) | It keeps recording the last few seconds without you asking, eating processor |
| Sets the power plan to **High Performance** | Stops Windows from saving power mid-match. If your machine doesn't have that option, it says so and moves on |
| Adjusts the **game's config file** | Turns off animations and effects that change nothing competitively. It makes a backup copy first |
| Tells Windows **which cores the graphics driver may use** | So it stops sharing a core with the game. This is the result of stage 3's measurement |
| Tells Windows **which cores the game may use** | To keep it away from the driver's core |
| Configures **Process Lasso** | High priority, and the ProBalance exclusion |

> One specific warning: the config file adjustment **turns off replay recording** for your matches (the
> `.rofl` files). If you use replays, the script tells you on screen how to put that back.

### What it downloads from the internet

This repository **contains nobody's software** — just two text files you can read before running.
During execution, and **only if you authorize it**, it downloads two tools, each from its own official
site:

- **AutoGpuAffinity** — the tool that measures the cores. Downloaded straight from the author's GitHub.
- **Process Lasso** — downloaded from Bitsum's site, and **only if you don't already have it**. The
  script checks the installer's digital signature before running it, and asks again if it isn't valid.

If you answer **no** to both, the script still does the stage 2 tweaks and writes the undo script.

### About Process Lasso being paid software

**It is paid** (a one-time license, not a subscription). But **the free version covers everything this
script uses** — [Bitsum themselves list](https://bitsum.com/howfree/) priority, cores and ProBalance as
free features, and say most people can use the program indefinitely without restriction.

Their one condition: **commercial use requires a purchase.** If you game at home, the free version
covers you. If it's a work machine or an internet café, buy the license.

### What it refuses to do

- **It doesn't disable Windows protections.** No touching UAC, Secure Boot or Memory Integrity. Those
  are **security** settings — your decision, not a side effect of an FPS script.
- **It doesn't install anything without asking.**
- **It doesn't copy settings from another machine.** That's the most common mistake in guides out
  there: telling you to copy the numbers that worked on someone else's PC. It can make your FPS worse.

This is the opposite of what those "optimization" packages sold online do. One of them, which I
analyzed during the diagnosis, **disabled UAC** — and its "revert" button didn't turn it back on.

---

## How much gain to expect

### Where the result came from, in order of importance

**1. Getting the graphics driver off the game's core.** This is what locked in the **stable 200 fps**.
It's the core of the project, and it's the part the script **measures on your machine** — because
which core is free and which one is in the way changes from PC to PC.

**2. Giving the game high priority.** This raised the average. On a machine where some program is
holding the game back, this part pays off even more.

**3. Everything else** — turning off background recording, power plan, config file. Crumbs, but free.

Item 1 is what matters here, and it **doesn't depend on you having anything installed or
misconfigured**. It depends on your graphics driver competing for a core with the game — which is
Windows' **default** behavior, because nobody ever told it to do otherwise.

### What this script does for you

| Your situation | What it does |
|---|---|
| **You have a dedicated graphics card** — most PCs that play LoL | **It does the main part.** Measures your cores one by one and gets the graphics driver off the game's core. Here that was the difference between "200 average, fluctuating" and **200 locked in** |
| **You use Process Lasso** (or any optimizer that touches priority) | On top of the main part, there's a real chance an **active brake** is on your game right now. [10-second check](#if-you-already-use-process-lasso-run-this-check) — if that's your case, add another gain on top |
| **Integrated graphics, or GPU at 95–100% in game** | I'm not going to sell you anything here: **your limit is the graphics card**, and shuffling cores doesn't raise that ceiling. [What to do in your case](#does-this-apply-to-me) |
| **Processor with 4 cores or fewer** | Does the measurement and the priority, but **asks first** before reserving a core — with few cores, giving one up may cost more than it returns |
| **Intel processor, 12th generation or newer** | Does the priority and the rest, but **doesn't touch the cores** — [for safety, and the reason is a good one](#cases-where-it-holds-back-on-purpose) |

The thing that ties it together: **the script measures before it changes anything.** It shows you the
ranking of your own cores on screen, and you see with your own eyes whether there's a difference on
your machine or not. If there isn't, it tells you — instead of applying a recipe and leaving you
wondering whether it worked.

### If you already use Process Lasso, run this check

With the **game open**, open Process Lasso and find `League of Legends.exe` in its list:

- If **"Restrained"** shows in the *Status* column → **that's your case, and it's the biggest-gain
  one.** There's a penalty being applied to your game right now.
- If **nothing shows** there → you don't have that penalty. What's left is the core part, which helps
  more with the drops than with the average.

Another sign of the same problem: priority showing as **`High-`**, with a small dash at the end. That
dash is Process Lasso itself telling you it lowered the game.

> ⚠️ **Heads up if you're going to install Process Lasso on your own:** ProBalance ships **enabled by
> default**. Installing it and leaving it as-is is **creating** the problem described here. The script
> already sets up the game's exclusion in the same run — but if you do it by hand, don't skip that part.

### And what it doesn't do in any case

This does **not turn your processor into a different one**. A 10-champion late-game fight is the
heaviest moment in the game, and FPS drops there on any PC. What holds high FPS even in that moment are
processors with a chunk of extra built-in memory (AMD's **X3D** models, like the 5700X3D or 9800X3D) —
LoL is one of the games that benefits most from them.

The goal here is to put you **at the ceiling of the PC you already have**, not above it. And if your
case is one of the "small" rows: **a small gain is still a gain.** What isn't fine is you expecting 200
fps, getting 15, and feeling cheated — which is why all of this is written down before you download
anything.

---

## Can this get me banned?

Fair question, because League uses **Vanguard**, an anti-cheat that runs deep in Windows and is strict
about anything touching the game.

**Nothing here touches the game.** It doesn't replace game files, doesn't inject code into it, doesn't
run alongside it, and doesn't interfere with the anti-cheat. What this script does is talk to
**Windows**, using the official options Windows itself offers: program priority, core distribution, and
a device setting. It's the same category of thing as changing your power plan.

In technical terms, for those who want the detail: **the tools used here don't inject code into the
game process.** AutoGpuAffinity changes device affinity in the Windows registry, and Process Lasso uses
Windows' official priority and affinity APIs. Neither one touches a game file.

If you're wondering about other things commonly recommended out there — swapping game files, skin mods,
programs that hook themselves into the process — [doc 04](docs/04-METODO-E-LICOES.md) has the list of
what was checked and the risk of each. **This project does none of them**, which is why they're not
described here.

---

## Cases where it holds back on purpose

Two situations where the script **deliberately** does less than it could, because getting it wrong
costs more than getting it right:

**Intel processors, 12th generation or newer.** These mix fast cores and slow efficiency cores on the
same chip. If the script sent the game to the slow ones by mistake, your FPS would **drop by half** —
and telling them apart reliably requires a technique that isn't implemented yet. So it **doesn't touch
the cores** on those processors, and does the rest. You miss out on a bit of gain, but you lose nothing.

**Processors with 4 or few cores.** The idea of reserving a whole core for the graphics driver was
measured on an 8-core processor, where it costs 12% of the total. On a 4-core it costs 25% — and nobody
measured whether it's worth it. The script asks you and **recommends no**.

In both cases, priority and ProBalance are still applied normally. That's the part with the most
payoff, and it doesn't depend on any of this.

---

## Documentation and tests

Everything stated here is on the record — **including the mistakes made** and the evidence that killed
each wrong guess along the way. **The documents are in Portuguese:**

| Document | About |
|---|---|
| [01-HARDWARE.md](docs/01-HARDWARE.md) | The machine and everything measured on it |
| [02-CASO-LOL.md](docs/02-CASO-LOL.md) | The full case: the match monitoring, the 16-core measurement, the research |
| [03-COMO-FUNCIONA-O-LOLBOOST.md](docs/03-COMO-FUNCIONA-O-LOLBOOST.md) | The script from the inside, for reading the code with context |
| [04-METODO-E-LICOES.md](docs/04-METODO-E-LICOES.md) | The method, what proved to be **placebo**, and what actually gets you banned |
| [05-PENDENCIAS.md](docs/05-PENDENCIAS.md) | What hasn't been done yet, and how much each item is expected to give |

The [`exemplo/`](exemplo/) folder has **this** machine's results, so you can see what format to expect —
**they are not values to copy.** They were measured over 1,058,139 frames.

And the detail that sums up the project's philosophy: in that measurement, the **average** across all
cores varied by only 2.9% between best and worst. If I had looked at the average, I would have concluded
it made no difference at all. The difference was in the **worst moments** — the worst core was nearly 3×
worse than the best precisely during the stutters, which is what you actually feel while playing.
**Looking at the wrong metric almost killed the finding.**

Tests live in [`testes/testar.ps1`](testes/testar.ps1) — 63 checks that run without changing anything on
your machine:

```bash
powershell -ExecutionPolicy Bypass -File testes/testar.ps1
```

---

## Who made this

Gabriel — I play LoL and make videos about the game at
**[@pingumonosylas](https://www.youtube.com/@pingumonosylas)** (in Portuguese). This project came out
of a problem of my own that I refused to accept as "weak PC".

If the script helped you, drop by. And if it **didn't** help, that's worth a comment too — knowing
which machine it failed on is what makes the next version better.

### Tools used

- [AutoGpuAffinity](https://github.com/valleyofdoom/AutoGpuAffinity) — valleyofdoom (GPL-3.0)
- [Process Lasso](https://bitsum.com/) — Bitsum
- [PresentMon](https://github.com/GameTechDev/PresentMon) — Intel

License: [MIT](LICENSE). Not affiliated with Riot Games or Bitsum. Use at your own risk.
