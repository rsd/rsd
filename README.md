# RSD

RSD is a command line helper to write custom bash scripts.

It minimizes the costs of writing customs scripts for specific tasks and remember later on.

The idea is to be fast to write code, easy to reuse and share between scripts.

## Instalation

```git clone https://github.com/rsd/rsd.git
```

## Usage

```rsd [rsd options] COMMAND [command options] [command arguments]
rsd [rsd options] --version
rsd [rsd options] --check-version
rsd [rsd options] --install PATH
```

### RSD Options

	--usage | --help | -h
		Display help usage.
	--version
		Return the RSD version.
	--check-version
		Compares the local version to the one in the repository.
	--install PATH
		Install RSD in the provided PATH
	--debug LEVEL | -d LEVEL
		Sets the debug level
	--lib-dir PATHs | -l PATHs | --libdir PATHs | --lib PATHs
		Coma separated paths to search for libraries.
	--no-local | -nl
		Do not switch to a local rsd copy on the same directory.
	--completion
		Support for bash completion.
	In completion mode, no command or action is actually executed.
	No command file should exec in global space.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.


## License
[MPL-2](https://choosealicense.com/licenses/mpl-2.0/)
