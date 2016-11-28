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

>1. I like that you start by really positive, and it seems pretty noble to do so.
However, I am thinking if you should start negative by describing how annoying
it would be to not have runtime loading?
2. Write out operating system?

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
"extra" argument is a reserved parameter for each process, it's the same
"extra" that will be passed to the restarted process's `code_change/3`
function.

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

Without closing the current `iex` session, apply the patch to the file and
compile the module:

    % patch kv.ex kv.ex.patch
    % elixir kv.ex

You may see a warning about redefining an existing module, this warning can be
safely ignored.

Now, in the still open `iex` session, let's being the black magic incantations:
> Do you mean "bring"?

    iex> :sys.suspend(KV)
    :ok
    iex> :sys.load_file KV
    {:module, KV}
    iex> :sys.change_code(KV, KV, 0, nil)
    :ok
    iex> :sys.resume(KV)
    :ok

Now, we should be able to test it again:

    iex> KV.get(:a)
    21:28:47.989 [info]  Elixir.KV: Handling get request for a
    42
    iex> KV.put(:b, 2)
    21:28:53.729 [info]  Elixir.KV: Handling put request for b:2
    :ok

Thus, we are able to hot-swap running code, without stopping, losing state, or
effecting processes waiting for that data.
> I like this summary line

But there are better ways to achieve this same result.
> Yay! I am now expecting to learn how.

### Example: `iex` ###

There are several functions available to us when using `iex` that essentially
perform the above actions for us:

*   `c/1`: compile file

*   `r/1`: (recompile and) reload module

The `r/1` helper takes an atom of the module to reload, `c/1` takes a binary of
the path to the module to compile. Check the [documentation][30] for more
information.

Therefore, using these, we can simplify what we did in the previous example to
simply a call to `r/1`:

    iex> r KV
    warning: redefining module KV (current version loaded from Elixir.KV.beam)
      kv.ex:1

    {:reloaded, KV, [KV]}
    iex> KV.get(:a)

    21:52:47.829 [info]  Elixir.KV: Handling get request for a
    42

In one function, we have done what we did in 4. However, the story does not end
here. Although `c/1` and `r/1` are great for development. There are *not*
recommended for production use. Do not depend on them to perform deployments.
> So the issue _is_ performance? 

Therefore, we will need more tools for deployements.

## Relups ##

Fortunately, there is another set of tooling that allows us to more easily
deploy releases, and more topically, perform upgrades: Relups. Before we dive
straight into relups, let's discuss a few other related concepts.

### Erlang Applications ###

As part of Erlang "Applications", there is a related file, the [`.app`][16]
file. This resource file describes the application: other applications that
should be started and other metadata about the application.

Here's an example `.app` file from the [octochat][17] demo application:

    {application,octochat,
             [{registered,[]},
              {description,"Demo Application for How Swapping Code"},
              {vsn,"0.3.3"},
              {modules,['Elixir.Octochat','Elixir.Octochat.Acceptor',
                        'Elixir.Octochat.Application','Elixir.Octochat.Echo',
                        'Elixir.Octochat.ServerSupervisor',
                        'Elixir.Octochat.Supervisor']},
              {applications,[kernel,stdlib,elixir,logger]},
              {mod,{'Elixir.Octochat.Application',[]}}]}.

This is a pretty good sized "Erlang" triple. It tells it is an `application`,
the application's name is `octochat`, and everything in the list that follows
is a keyword list that describes the `octochat` application.

### Erlang Releases ###

Erlang "releases", similar to Erlang applications, are an entire system: the
Erlang VM, the dependent set of applications, and arguments for the Erlang VM.

After building a release for the Octochat application with the
[`distillery`][4] project, we get a `.rel` file similar to the following:

    {release,{"octochat","0.3.3"},
         {erts,"8.1"},
         [{logger,"1.3.4"},
          {compiler,"7.0.2"},
          {elixir,"1.3.4"},
          {stdlib,"3.1"},
          {kernel,"5.1"},
          {octochat,"0.3.3"},
          {iex,"1.3.4"},
          {sasl,"3.0.1"}]}.

This is an Erlang 4-tuple; it's a "release" of the "0.0.3" version of
"octochat". It will use the "8.1" version of "erts" and it depends on the list
of applications (and their versions) provided in the last element of the tuple.

### Appups and Relups ###

As the naming might suggest, "appups" and "relups" are the "upgrade" versions
for applications and releases, respectively. Appups describe how to take a
single application and upgrade its modules, specifically, it will have
instructions for upgrading modules that require "extras", or, if we are
upgrading supervisors, for example, it will have the correct instructions for
adding and removing child processes.

Let's examine some examples of these files as well. Here is an appup for
octochat generated using [distillery][4]:

    {"0.2.1",
     [{"0.2.0",[{load_module,'Elixir.Octochat.Echo',[]}]}],
     [{"0.2.0",[{load_module,'Elixir.Octochat.Echo',[]}]}]}.

This triple tells us how to take the octochat application from the "0.2.0"
version to the "0.2.1" version, specifically what module needs to be updated to
make the application upgrade a success. Notice, this is only one module, to
upgrade the application, we do not need to update _every_ module, only the
module with _actual_ changes. The last element of the tuple instructs how to
"downgrade" from "0.2.1" to "0.2.0". The instructions make sense here, since it
is similarly, only a change in the single module.
> Actually, it does not make sense. I don't understand what is going on here.

Now, let's look at the related "relup" file for this release:

    {"0.2.1",
     [{"0.2.0",[],
       [{load_object_code,{octochat,"0.2.1",['Elixir.Octochat.Echo']}},
        point_of_no_return,
        {load,{'Elixir.Octochat.Echo',brutal_purge,brutal_purge}}]}],
     [{"0.2.0",[],
       [{load_object_code,{octochat,"0.2.0",['Elixir.Octochat.Echo']}},
        point_of_no_return,
        {load,{'Elixir.Octochat.Echo',brutal_purge,brutal_purge}}]}]}.

Notice, this is a triple as well. This triple tells more of the story of how to
deploy the upgrade from 0.2.0 to 0.2.1. Let's break down just the upgrade
instructions for now:


    [{load_object_code,{octochat,"0.2.1",['Elixir.Octochat.Echo']}},
     point_of_no_return,
     {load,{'Elixir.Octochat.Echo',brutal_purge,brutal_purge}}]

The first instruction tells the VM to load into memory the new version of the
"Octochat.Echo" module, specifically the one associated with version "0.2.1".
But do not start or replace anything yet. Next, it tells the VM, that failure
beyond this point is fatal, if the upgrade fails from this point on, backing
out will require manual intervention(?). The final step is to replace the
running version of the module and use the newly loaded version. For more
information regarding `burtal_purge`, check out the "PrePurge" and "PostPurge"
values in the [appup documentation][18].

Similar to the appup file, the third element in the triple describes to the
Erlang VM how to downgrade the release as well. The version numbers in this
case make this a bit more obvious as well, however, the steps are essentially
the same.
> Whenver you refer to section in code maybe add in parentheses what I should
be looking at? For example, "the third element (point_of_no_return)"

### Generating Releases and Upgrades with Elixir ###

Now that we have some basic understanding of releases and upgrades, let's see
how we can generate them with Elixir. For the first version, we will generate
the releases with the [distillery][4] project.

> This has been written for the `0.10.1` version of [distillery][4]. This is a
> fast moving project that is in beta, be prepared to update as necessary.

Add the application to your `deps` list:

    {:distillery, "~> 0.10"}

Perform the requisite dependency download:

    ± mix deps.get

Then, to build your first release, you can use the following:

    ± MIX_ENV=prod mix release --env prod

> For more information on why you must specify both environments, please read
> the [FAQ][19] of distillery. If the environments match, there's a small
> modification to the `./rel/config.exs` that can be made so that specifying
> both is no longer necessary.

After this process is complete, there should be a new folder under the `./rel`
folder that contains the new release of the project. Within this directory,
there will be several directories, namely, `bin`, `erts-8.1`, `lib`, and
`releases`. The `bin` directory will contain the top level Erlang entry
scripts, the `erts-{version}` folder will contain the requisite files for the
Erlang runtime, the `lib` folder will contain the compiled beam files for the
required applications for the release, and finally, the `releases` folder will
contain the versions of the releases. Each folder for each version will have
its own `rel` file, generated boot scripts, as per
the [OTP releases guide][20], and a tarball of the release for deployment.

Next, we can generate an upgrade for the release using the following command:

    ± MIX_ENV=prod mix release --upgrade

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

[15]: http://elixir-lang.org/docs/stable/iex/IEx.Helpers.html

[16]: http://erlang.org/doc/man/app.html

[17]: https://git.devnulllabs.io/demos/octochat.git

[18]: http://erlang.org/doc/man/appup.html

[19]: https://hexdocs.pm/distillery/common-issues.html#why-do-i-have-to-set-both-mix_env-and-env

[20]: http://erlang.org/doc/design_principles/release_structure.html
