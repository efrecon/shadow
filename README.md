# shadow

`shadow` will copy one or several files or directories from a source to a target
directory before executing a command. This script has minimal requirements and
can be useful when copying templates prior to execute a daemon or similar.
`shadow` is able to perform copies through `sudo`, whenever the source directory
has restrictive permissions.  Also, running the script with the same arguments,
but the command-line option `--delete` will delete all relevant target files.

`shadow` is tuned to be used as the entrypoint to a Docker container, for
example for copying a secret file before it is used and modified further on. As
such, it can be configured through environment variables starting with `SHADOW_`
or through command-line options. Command-line options have precedence over the
environment variables.

## Examples

### Using Configuration Files

Run from the main directory, the following example would copy this script and
the test configuration file to the `/tmp` directory. Once done, it would output
a long listing of the `/tmp` directory. This is because the test configuration
file [contains][test] relative paths to the script and itself.

```shell
./shadow.sh -c test/shadow.cfg -s . -d /tmp -- ls -l /tmp
```

  [test]: ./test/shadow.cfg

### Using Repetitive Command-Line Options

Run from the main directory, the following example achieves exactly the same.

```shell
./shadow.sh -p test/shadow.cfg -p shadow.sh -s . -d /tmp -- ls -l /tmp
```

### Combining Both Techniques

Run from the main directory, the following example also copies this `README.md`
file.

```shell
./shadow.sh -c test/shadow.cfg -p README.md -s . -d /tmp -- ls -l /tmp
```
