# spinach

BDD Style spec runner for Crystal. This project is fairly experimental and was written in a day so will be gradually improved over time. Please raise any feature requests or bugs.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     spinach:
       github: sushichain/spinach
   ```

2. Run `shards install`

## Usage

```crystal
require "spinach"
```

The basic concept is that you write executable specifications in an HTML file that has a companion supporting crystal file. You then execute the crystal file and it will execute a spec and produce an augmented HTML file with the results.

You put your html file and supporting crystal file in the `spec` folder.

There are 3 directives:

* assert_equals
* set
* execute

In your HTML you use these to write the specs. See below. See also the specs of this project for examples.

### Set Variable

```html
<p>
  If my username is <b spinach:set="#username">Chuck Norris</b>.
  Then the system should greet me with <b spinach:assert_equals="greeting_for(#username)">Hello Chuck Norris</b>.
</p>
```
This will set the value `Chuck Norris` onto a variable called `#username` which you can use in a later assert_equals to assert a value.

![](.README/set_variable.png)

### Assert Equals

```html
<blockquote>
  The greeting should be <b spinach:assert_equals="get_greeting()">Hello World!</b>.
</blockquote>
```

This will assert the value returned by the method `get_greeting` with the supplied text: `Hello World!`

The return type of `get_greeting` **MUST** be a `String`

![](.README/assert_equals.png)

A second way to use assert_equals is when there is just a variable being asserted - either that has been set in the html or that is the result of an execute.


```html
<p>
  If my name is <b spinach:set="#username">Chuck Norris</b>.<br/>
  Then my username should be <b spinach:assert_equals="#username">Chuck Norris</b>.
</p>
```

![](.README/assert_equals_with_variable.png)

### Execute

```html
<p spinach:execute="#greeting = greeting_for(#firstname, #lastname)">
  The greeting <b spinach:assert_equals="#greeting.login_greeting">Hello Bob!</b><br/>
  And the message <b spinach:assert_equals="#greeting.login_message">Your last name is Bobbington!</b><br/>
  should be given to user <b spinach:set="#firstname">Bob</b> <b spinach:set="#lastname">Bobbington</b><br/>
  when he logs in.
</p>
```

This will store the result of the method `greeting_for` in a result `HashMap` which you can then use in later asserts.

When returning a result in an execute you **MUST** return a `HashMap`

![](.README/execute_function.png)

## Running

To run a spec you can do the following:

`crystal run spec/*.cr` or `crystal run spec/individual_file.cr`

if you want to put your specs somewhere else you can also do this:

`crystal run spec/spinach/*.cr -- -l "spec/spinach"`

There is a basic command line report:

![](.README/cli.png)


## Writing Specs

In the `spec` folder of your project you write 2 files:

1. assert_something.cr
2. assert_something.html

The names of the files must be the same. Also the name of the class in the crystal file must be the camel case equivalent of the file name. e.g. assert_something.cr must have a class called `AssertSomething`

here is an example of the files:

```crystal
class AssertEquals < SpinachTestCase

  def mapping
    {
      "get_greeting": ->(args : Array(String)){ get_greeting }
    }
  end

  def get_greeting
    "Hello World!"
  end

end
```

You must extend from `SpinachTestCase`. You must also provide a mapping between the base name of the method and a proc containing the methods to execute during the running of the spec.

The Proc **MUST** always be in the format: `->(args : Array(String){ some_method_call }`
The method can optionally take the arguments if needed.

```html
<html>

<head>
  <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootswatch/4.3.1/spacelab/bootstrap.min.css">
</head>

<body>
  <div class="container">
    <h1>Assert Equals</h1>
    <h4>This is an example of a basic assertion using <b>assert_equals</b>.</h4>
    <p>
      <blockquote>
        The greeting should be <b spinach:assert_equals="get_greeting()">Hello World!</b>.
      </blockquote>
    </p>
  </div>
</body>

</html>
```

## Contributing

1. Fork it (<https://github.com/sushichain/spinach/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Kingsley Hendrickse](https://github.com/kingsleyh) - creator and maintainer
