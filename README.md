# zilsutra
Zilsutra is meant to be a universal simulator for any microcontrollers and/or microprocessors.

## Why?
I could not find any suitable open-source simulator for the new ATtiny 0 family of microcontrollers. The only ones I found either did not work, or were closed-source and I could not use them on their own but had to pull a gigantic IDE with a specific license tied to it, and would not let me simulate raw assembly, but only whatever its specific custom version of AVR-GCC was spitting out. I am not going to name names, but they know who they are. And there was another category of simulators, those that would not let me single step, or give me proper debugging capabilities over the simulation.

Zilsutra is meant to solve this pain of mine, but I have built it such that it is generic and configurable, you could theoretically simulate absolutely any and all microcontrollers and microprocessors that have registers and instructions.

The trick is that you have to define these yourself. That is, the registers and the instructions (and what they do).
Zilsutra aids you here and writes most of the boilerplate for you already, and has a lot of functions to let you implement your very own specific instructions using a library of generics that are quasi-architecture-independent, which can be immediately specialized for your own architecture.

Zilsutra is not really just a simulator, but an entire framework for defining registers, instructions, architectures, and devices, letting you interconnect them, and simulate their behaviour in whichever way you desire.

Of course, the main goal is just to simulate things, but the code is CC0 licensed for a reason: do as you wish with it.

Also, unlike some _other_ projects, which have inspired me do make this one (but mostly out of spite and anger that you could not easily implement another simulation targets), this is not tied to any UI interface, nor does it have any other dependencies than Zig itself in order to compile stuff with it, this is just a library, you can use it wherever you want, as long as you know how to use it (documentation and over-all view of the architecture of Zilsutra is still a work-in-progress).
