# NORA

NORA (named because she "brings P-A-NORA-M-A together") is a Ruby gem that
schedules meetings between coworkers and adds them to Google Calendar without
any work on the part of the coworkers.

We use these meetings (we call them "NORAs") to get to know one another better,
grab coffee, brainstorm new ideas... whatever tickles our fancy
at the time. But you can choose to be as strict or as loose about your
organization's NORAs as you like.

**NOTE: This code is experimental. It works for us, but if it doesn't work for
you we'd love to hear about it so we can make it better.**

## Installation

1. `gem install nora`
2. Use [Google's Developer Console](https://console.developers.google.com/projectselector/apis/credentials)
to create a new project and a new OAuth 2.0 client ID for NORA to use. Download
that file and rename it `nora_client_secret.json`.
3. Obtain a [SendGrid](https://sendgrid.com) username and password. (This is
used for sending emails when scheduling.) If you use Heroku, you can obtain a
username and password easily by adding the free SendGrid add-on and then using
the username and password that are set automatically in config variables.
4. Copy the [`examples/nora_configuration.json`](https://github.com/panorama-ed/nora/blob/master/examples/nora_configuration.json) file from this repo into the folder from
which you intend to run the `nora` program. Edit the file to include the names
and email addresses you want, your SendGrid credentials, and any other changes
you like.
5. While logged in to Google Calendar (as the user you intend to run NORA as,
which is most likely yourself), use the "Add a friend's/coworker's calendar"
box to add the calendars for everyone you added to your
`nora_configuration.json` file. *Note that this step may not be necessary but
not doing it can occasionally cause people to get skipped when scheduling.*

## Usage

Once you've gone through the installation steps above, you can schedule meetings
by running this command in your shell/terminal/console from the directory that
contains your `nora_configuration.json` and `nora_client_secret.json` files:

```bash
nora --weeks-ahead <how many weeks ahead to schedule>
```

For example:

```bash
nora --weeks-ahead 2
```

NORA automatically keeps track of who's been scheduled together in the past via
the `past_pairings.txt` file, so that the same folks don't get scheduled
together often.

#### Adding/Removing People

To add someone for future scheduling, simply add their name and email address
to `nora_configuration.json`, and add them to your Google Calendar as you did in
installation step 5.

To remove someone, just remove them from `nora_configuration.json`.

## Troubleshooting

#### NORA isn't scheduling someone!

Make sure that they're in the `nora_configuration.json` file with the correct
email address, and that you've also added their email to the Google Calendar of
the user running NORA (see installation step 5).

#### NORA is scheduling events at the same time as full-day events!

Unfortunately this is due to a bug in how Google Calendar calculates when
someone is "busy." See
[here](https://productforums.google.com/forum/#!topic/calendar/qAOwI540nu4) for
more details.

#### I'm seeing "Authorization failed" errors!

NOTE: If you consistently get errors that look like this:

```
/Users/jacobevelyn/.gem/ruby/2.2.0/gems/signet-0.7.2/lib/signet/oauth_2/client.rb:981:in `fetch_access_token': Authorization failed.  Server message: (Signet::AuthorizationError)
{
  "error": "invalid_grant",
  "error_description": "Bad Request"
}
    from /Users/jacobevelyn/.gem/ruby/2.2.0/gems/signet-0.7.2/lib/signet/oauth_2/client.rb:998:in `fetch_access_token!'
    ...
```

then all you need to do is delete the credentials file and re-run the program.
This will create a new credentials file.

#### I have another question or issue!

No problem! Simply create a GitHub Issue and we'll get you straightened out.

## Contributing

1. Fork it (https://github.com/panorama-ed/nora/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

**Make sure your changes conform to the Rubocop style specified.** We use
[overcommit](https://github.com/causes/overcommit) to enforce consistent code.

## License

The gem is available as open source under the terms of the [MIT License](https://github.com/panorama-ed/nora/blob/master/LICENSE.txt).
