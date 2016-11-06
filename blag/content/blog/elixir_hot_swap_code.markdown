---
title: "Elixir/Erlang Hot Swapping Code"
description: "Hot code reloading with Elixir and Erlang"
tags:
  - "Erlang/OTP"
  - "Elixir"
  - "How-to"
  - "Tips and Tricks"
date: "2016-11-07"
categories:
  - "Development"
slug: "elixir-hot-swapping"
---

{{<youtube xrIjfIjssLE>}}

> Warning, there be black magic here.

One of the untold benefits of having a runtime is the ability for that runtime
to enable loading and unloading code while the runtime is active. Since the
runtime is itself, essentially, a virtual machine with its own OS and process
scheduling, it has the ability to start and stop, load and unload, processes
and code similar to how "real" operating systems do.

This enables some spectacular power in terms of creating deployments and
rolling out those deployments. That is, if we can provide a particular artifact
for the runtime to load and replace the running system with, we can instruct it
upgrade our system(s) _without_ restarting them, without interrupting our
services or affecting users of those systems. Furthermore, unlike other systems
like [Docker][13] or [Kubernetes][14], Erlang releases will happen in seconds,
not hours or days, because the system can be transitioned nearly
instantaneously because of Erlang's functional approach.

This post will be a small tour through how Elixir and Erlang can perform code
hot swapping, and how this can be useful for deployments.

## Hot Code Swapping: Basics ##

There are several functions defined in the [`:sys`][5] and [`:code`][6] modules
that are required for this first example. Namely, the following functions:

*   `:sys.suspened/1`

*   `:sys.resume/1`

*   `:code.load_file/1`

*   `:sys.change_code/4`

The `:sys.suspend/1` function takes a single parameter, the Process ID (PID) of
the process to suspend, similarly, `:sys.resume` also takes a PID of the
process to resume. The `:code.load_file/1` function, unfortunately named, takes
a single argument: the _module_ to load into memory. Finally, the
`:sys.change_code` function takes four parameters: "name", module, old version,
and "extra". The "name" is the PID or the registered name of the process. The
"extra" argument is reserved parameter for each process, it's the same "extra"
that will be passed to the restarted process's `code_change/3` function.

### Example ###

Let's assume we have a particularly simple module, say `KV`, similar to the
following:

    defmodule KV do
      use GenServer

      @vsn 0

      def start_link() do
        GenServer.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(_) do
        {:ok, %{}}
      end

      def get(key, default \\ nil) do
        GenServer.call(__MODULE__, {:get, key, default})
      end

      def put(key, value) do
        GenServer.call(__MODULE__, {:put, key, value})
      end

      def handle_call({:get, key, default}, _caller, state) do
        {:reply, Map.get(state, key, default), state}
      end

      def handle_call({:put, key, value}, _caller, state) do
        {:reply, :ok, Map.put(state, key, value)}
      end

    end

Save this into a file, say, `kv.ex`. Next we will compile it and load it into
an `iex` session:

    % elixirc kv.ex
    % iex
    iex> l KV
    {:module, KV}

We can start the process and try it out:

    iex> KV.start_link
    {:ok, #PID<0.84.0>}
    iex> KV.get(:a)
    nil
    iex> KV.put(:a, 42)
    :ok
    iex> KV.get(:a)
    42

Now, let's say we wish to add some logging to the handling of the `:get` and
`:put` messages. We will apply a patch similar to the following:

    diff --git a/src/demo/1/kv.ex b/src/demo/1/kv.ex
    index b37aead..03adc7e 100644
    --- a/src/demo/1/kv.ex
    +++ b/src/demo/1/kv.ex
    @@ -1,7 +1,8 @@
     defmodule KV do
    +  require Logger
       use GenServer

    -  @vsn 0
    +  @vsn 1

       def start_link() do
         GenServer.start_link(__MODULE__, [], name: __MODULE__)
    @@ -20,10 +21,12 @@ defmodule KV do
       end

       def handle_call({:get, key, default}, _caller, state) do
    +    Logger.info("#{__MODULE__}: Handling get request for #{key}")
         {:reply, Map.get(state, key, default), state}
       end

       def handle_call({:put, key, value}, _caller, state) do
    +    Logger.info("#{__MODULE__}: Handling put request for #{key}:#{value}")
         {:reply, :ok, Map.put(state, key, value)}
       end

Without closing the current `iex` session, apply the patch to the file:

    % patch kv.ex kv.ex.patch

[1]: http://erlang.org/doc/reference_manual/code_loading.html

[2]: https://github.com/bitwalker/exrm

[3]: https://github.com/erlware/relx

[4]: https://github.com/bitwalker/distillery

[5]: http://erlang.org/doc/man/sys.html

[6]: http://erlang.org/doc/man/code.html

[7]: http://elixir-lang.org/docs/stable/elixir/

[8]: http://elixir-lang.org/docs/stable/elixir/Code.html

[9]: http://erlang.org/doc/man/relup.html

[10]: http://andrealeopardi.com/posts/handling-tcp-connections-in-elixir/

[11]: https://git.devnulllabs.io/demos/octochat.git

[12]: https://www.youtube.com/watch?v=xrIjfIjssLE

[13]: https://docker.com

[14]: http://kubernetes.io/
