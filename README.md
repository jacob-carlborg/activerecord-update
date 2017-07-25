# activerecord-update [![Build Status](https://travis-ci.org/jacob-carlborg/activerecord-update.svg?branch=master)](https://travis-ci.org/jacob-carlborg/activerecord-update)

activerecord-update is a library for doing batch updates using ActiveRecord.
Currently it only supports PostgreSQL.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activerecord-update'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install activerecord-update

## Usage

All ActiveRecord classes have two new class methods added, `update_records` and
`update_records!`. Both expect an array of ActiveRecord models. The difference
between these methods is that `update_records!` will raise an error if any
validations fail or any stale objects are identified, if optimistic locking is
enabled.

```ruby
class Book
  validates :title, presence: true
end

books = Book.find(1, 2, 3)
books.each_with_index { |book, index| book.title = "foo_#{index}" }
Book.update_records(books)

books.each { |book| book.title = nil }
Book.update_records!(books) # will raise an ActiveRecord::RecordInvalid error
```

## Supported Versions

* Ruby 1.9.3 or later
* ActiveRecord 2.3.x and 4.1.x

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then,
run `rake spec` to run the tests. You can also run `bin/console` for an
interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.
To release a new version, update the version number in `version.rb`, and then
run `bundle exec rake release`, which will create a git tag for the version,
push git commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/jacob-carlborg/activerecord-update.

