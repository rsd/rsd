# TODO ideias to improvement

## Getops | shlibs

Use external libs to parse arguments in shell scripts more gracefully.
The main rsd script can't relly on external libs to keep as a self installable script.
However, after installed, it can.

So, the main rsd script should do as little as possible regarding options parsing.

After installed, it can use external libs to parse options thru a internal lib.

Still have to study and understand the options avaliable to be able to go for a way or another.

# Automation

Some repeated tasks could be automated for the user into a composed command sequence.

# Remote Execution

There should be more features regarding remote execution.
This envolves possibilities from ssh to lxc and docker.
So that rsd does not necessarilly need to be installed into a remote machine or container.
Even so, somekind of communication could be stablished, for example to handle backups and restores from remote 
enviroments.

# Removed Features

Some features have being removed from the original rsd script.
Like caching.  Caching and other performance related features were remove in favor of simplicity and readability.
As a shell scripts that run external commands, the little gain on performance in negligent.

Caching is not to be confused with configuration or automation for tasks.

