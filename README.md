Exedb
-----

This is simple Ruby class, which implements
database-like interface for executables.

For example:

```ruby
e=Exedb.new("my_long_working_exe arg1 arg2")
e.cache_timeout=10 # 10 seconds timeout

e.get # run and return exe output
e.get # just return exe output again!
sleep 10
e.get # run exe again (cache is timed out)
e.update # run exe and update cache NOW!
```

If one exe is running another instance on the
same Exedb will wait for it.


Methods and constants
---------------------

- ::new(str=nil) - create new instance, str=exec line
- ::DEF_DIR - default dir for cache files
- ::DEF_CACHE_TIMEOUT - default cache timeout

- #get - get exe output
- #update - run exe anyway, return output

Accessors
--------

- cache_timeout
- cache_dir

