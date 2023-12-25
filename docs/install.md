---
title: Installation
layout: default
nav_order: 2
---

**Installation**

Luagram has native support for various platforms:

- **[Redbean](https://redbean.dev/):** Open-source web server in a zip executable that runs on six operating systems. Primary platform.

- **[OpenResty](http://openresty.org/en/):** High-performance web platform based on Nginx and LuaJIT. Requires the [Lapis](https://leafo.net/lapis/) web framework package installed.

- **[Fengari](https://fengari.io/):** Lua VM written in JS ES6 for Node and the browser.

If none of these platforms is detected, Luagram will attempt to require the `ssl.https` module.

To start using Luagram, you should have downloaded the `Luagram.lua` file from our repository. There are several ways to do this.

**Manual:**

Download our repository manually [here](http://github.com/Propagram/Luagram/). Then extract the zip into a folder.

**Via [git](https://git-scm.com/):**

Clone our repository:

 `git clone https://github.com/Propagram/Luagram.git`

**Via [Luarocks](https://luarocks.org/):**

Execute the command:

 `luarocks install Luagram`