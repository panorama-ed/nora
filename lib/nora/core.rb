# frozen_string_literal: true

require "google/apis/calendar_v3"
require "googleauth"
require "googleauth/stores/file_token_store"

require "fileutils"

require "active_support"
require "active_support/core_ext/time/zones"
require "active_support/core_ext/numeric/time"
require "active_support/duration"
require "chronic"
require "pony"

module Nora
  class Core
    extend Memoist

    PAIRINGS_FILE = "past_pairings.txt"
    PAIRINGS_FILE_SEPARATOR = " "

    OOB_URI = "urn:ietf:wg:oauth:2.0:oob"
    CLIENT_SECRETS_PATH = "nora_client_secret.json"
    CREDENTIALS_PATH = "calendar-ruby-quickstart.yaml"
    SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR

    FREE_BUSY_QUERY_BATCH_SIZE = 5

    CONFIGURATION = JSON.parse(File.read("nora_configuration.json"))

    Pony.options = {
      via: :smtp,
      via_options: {
        address: "smtp.sendgrid.net",
        port: "587",
        domain: CONFIGURATION["email"]["domain"],
        authentication: :plain,
        enable_starttls_auto: true,

        # These Sendgrid credentials come from the Heroku addon.
        user_name:
          CONFIGURATION["email"]["sendgrid_configuration"]["user_name"],
        password: CONFIGURATION["email"]["sendgrid_configuration"]["password"]
      }
    }

    def initialize(weeks_ahead:, test:)
      puts

      @weeks_ahead = weeks_ahead
      @test = test

      FileUtils.touch(PAIRINGS_FILE) # Make sure pairings file exists.

      # Set global Chronic parsing time zone.
      Time.zone = "UTC"
      Chronic.time_class = Time.zone

      # Initialize the API
      @service = Google::Apis::CalendarV3::CalendarService.new
      @service.client_options.application_name =
        CONFIGURATION["calendar"]["application_name"]
      @service.authorization = authorize
    end

    def run!
      begin
        load_history!
        puts "Loading calendars..."
        load_calendars!
        puts "Creating groups..."
        create_groups!
      rescue SystemStackError
        remove_oldest_pair!

        retry
      end

      send_emails(
        template_emails_for(
          schedule_meetings!
        )
      )

      puts "Done."
    end

    private

    # Adds all calendars to NORA's calendar, so that
    # `@service.list_calendar_lists` will have every
    # calendar in the configuration file without us
    # having to manually add them in the UI.
    def load_calendars!
      @emails.each do |email|
        @service.insert_calendar_list(
          Google::Apis::CalendarV3::CalendarListEntry.new(id: email)
        )
      end
    end

    def remove_oldest_pair!
      puts "Removing oldest pair and retrying..."
      File.open("past_pairings_tmp.txt", "w") do |file|
        File.open(PAIRINGS_FILE).each.with_index(1) do |line, line_num|
          file.puts(line) unless line_num == 1
        end
      end
      FileUtils.mv("past_pairings_tmp.txt", PAIRINGS_FILE)
    end

    def load_history!
      puts "Loading history..."
      @history = Set.new
      File.open(PAIRINGS_FILE).each do |line|
        line.split(PAIRINGS_FILE_SEPARATOR).permutation.each do |emails|
          @history << emails
        end
      end
    end

    def create_groups!
      @emails = CONFIGURATION["people"].map { |p| p["email"] }.shuffle
      @emails.each_slice(group_size).each do |emails|
        return create_groups! unless (@history & emails.combination(2)).empty?
      end
    end

    # @return [Array<Hash>] list of meetings, of the format:
    #   { on: <Time>, who: [{ email: ..., name: ... }, ...] }
    def schedule_meetings!
      puts "Scheduling meetings..."

      meetings = []

      @emails.each_slice(group_size) do |emails|
        if emails.size < group_size
          puts "\nNot enough people in group: #{emails}\n"
          meetings << {
            on: :no_group,
            week_of: availability_schedule.keys.first,
            who: emails.map do |email|
              { email: email, name: email_name(email) }
            end
          }
          next
        end

        time = availability_schedule.select do |_, ids|
          ids.superset? Set.new(emails)
        end.keys.sample

        if time.nil?
          puts "\nNo time found for #{emails}\n"
          meetings << {
            on: :no_time,
            week_of: availability_schedule.keys.first,
            who: emails.map do |email|
              { email: email, name: email_name(email) }
            end
          }
        else
          puts "#{time} => #{emails}"
          add_meeting(time: time, attendee_ids: emails)

          unless @test
            File.open(PAIRINGS_FILE, "a") do |file|
              emails.combination(2) do |email_pair|
                file.puts email_pair.join(PAIRINGS_FILE_SEPARATOR)
              end
            end
          end

          meetings << {
            on: time,
            who: emails.map do |email|
              { email: email, name: email_name(email) }
            end
          }
        end
      end

      meetings
    end

    def template_emails_for(appointments)
      appointments.map do |appt|
        names = appt[:who].map { |w| w[:name] }.join(" and ")

        # rubocop:disable Layout/MultilineMethodCallIndentation
        message =
          case appt[:on]
          when :no_time
            num_weeks = @weeks_ahead + 1
            CONFIGURATION["email"]["templates"]["no_time"].
              gsub("NAMES", names).
              gsub("ICEBREAKER", icebreaker).
              gsub("WEEKS_AHEAD", "#{num_weeks} #{'week'.pluralize(num_weeks)}")
          when :no_group
            num_weeks = @weeks_ahead + 1
            CONFIGURATION["email"]["templates"]["no_group"].
              gsub("WEEKS_AHEAD", "#{num_weeks} #{'week'.pluralize(num_weeks)}")
          else
            datetime = appt[:on].in_time_zone("Eastern Time (US & Canada)")
            day = datetime.strftime("%B %-d")
            military_time = datetime.strftime("%H%M")

            CONFIGURATION["email"]["templates"]["default"].
              gsub("NAMES", names).
              gsub("DAY", day).
              gsub("MILITARY_TIME", military_time).
              gsub("ICEBREAKER", icebreaker)
          end
        # rubocop:enable Layout/MultilineMethodCallIndentation

        {
          to: appt[:who],
          subject: "NORA: Mission Briefing",
          body: message
        }
      end
    end

    def send_emails(email_messages)
      return if @test

      puts "Sending emails..."

      email_messages.each do |msg|
        msg[:to].each do |to|
          begin
            Pony.mail(
              to: to[:email],
              from: CONFIGURATION["email"]["from_address"],
              subject: msg[:subject],
              body: msg[:body],
              via: :smtp,
              charset: "UTF-8"
            )
          rescue => e
            puts e
          end
        end
      end
    end

    def add_meeting(time:, attendee_ids:)
      return if @test

      @service.insert_event(
        CONFIGURATION["calendar"]["id"],
        Google::Apis::CalendarV3::Event.new(
          summary:
            "NORA: #{attendee_ids.map { |id| email_name(id) }.join('/')}",
          description: "Icebreaker question: #{icebreaker}",
          start: Google::Apis::CalendarV3::EventDateTime.new(
            date_time: time.to_datetime
          ),
          end: Google::Apis::CalendarV3::EventDateTime.new(
            date_time: (
              time + CONFIGURATION["calendar"]["duration_in_minutes"]
            ).to_datetime
          ),
          attendees: attendee_ids.map do |id|
            Google::Apis::CalendarV3::EventAttendee.new(email: id)
          end,
          guests_can_modify: true
        )
      )
    end

    def availability_schedule
      # Compute Hash of all possible times to set of all user IDs.
      # rubocop:disable Metrics/LineLength
      all_availabilities = CONFIGURATION["calendar"]["days_of_week"].flat_map do |day|
        # rubocop:enable Metrics/LineLength
        CONFIGURATION["calendar"]["start_times"].map do |time|
          Chronic.parse("#{@weeks_ahead} weeks from next #{day} #{time}").utc
        end
      end.each_with_object({}) do |time, h|
        h[time] = Set.new(calendars.map(&:id))
      end

      # Remove user IDs due to business constraints.
      calendars.each_slice(FREE_BUSY_QUERY_BATCH_SIZE) do |cals|
        @service.query_freebusy(
          Google::Apis::CalendarV3::FreeBusyRequest.new(
            time_min: start_of_week.iso8601,
            time_max: end_of_week.iso8601,
            time_zone: "UTC",
            items: cals.map { |cal| { id: cal.id } }
          )
        ).calendars.each do |id, free_busy|
          free_busy.busy.each do |busy_period|
            all_availabilities.each do |time, ids|
              if (busy_period.start.to_time <= (
                time + CONFIGURATION["calendar"]["duration_in_minutes"] -
                1.minute
              )) && (busy_period.end.to_time >= (time + 1.minute))
                ids.delete(id)
              end
            end
          end
        end
      end

      # Now remove hash values that have <2 IDs in their set.
      all_availabilities.select { |_, ids| ids.size > 1 }
    end
    memoize :availability_schedule

    def icebreaker
      CONFIGURATION["icebreakers"].sample
    end
    memoize :icebreaker

    def email_name(email)
      email_name_map[email]
    end

    def email_name_map
      CONFIGURATION["people"].each_with_object({}) do |data, h|
        h[data["email"]] = data["name"]
      end
    end
    memoize :email_name_map

    def calendars
      @service.list_calendar_lists.items.select do |calendar|
        @emails.include? calendar.id
      end
    end
    memoize :calendars

    def start_of_week
      Chronic.parse(
        # rubocop:disable Metrics/LineLength
        "#{@weeks_ahead} weeks from next #{CONFIGURATION['calendar']['days_of_week'].first} "\
        "#{CONFIGURATION['calendar']['start_times'].first}"
        # rubocop:enable Metrics/LineLength
      )
    end
    memoize :start_of_week

    def end_of_week
      date_time = (
        Chronic.parse(
          # rubocop:disable Metrics/LineLength
          "#{@weeks_ahead} weeks from next #{CONFIGURATION['calendar']['days_of_week'].last} "\
          "#{CONFIGURATION['calendar']['start_times'].last}"
          # rubocop:enable Metrics/LineLength
        ) + CONFIGURATION["calendar"]["duration_in_minutes"].minutes
      )

      if date_time > start_of_week
        date_time
      else
        date_time + 7.days
      end
    end
    memoize :end_of_week

    # Ensure valid credentials, either by restoring from the saved credentials
    # files or intitiating an OAuth2 authorization. If authorization is
    # required, the user will be instructed appropriately.
    # @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
    def authorize
      FileUtils.mkdir_p(File.dirname(CREDENTIALS_PATH))

      client_id = Google::Auth::ClientId.from_file(CLIENT_SECRETS_PATH)
      token_store = Google::Auth::Stores::FileTokenStore.
                    new(file: CREDENTIALS_PATH)
      authorizer = Google::Auth::UserAuthorizer.
                   new(client_id, SCOPE, token_store)
      credentials = authorizer.
                    get_credentials(CONFIGURATION["calendar"]["user_id"])
      if credentials.nil?
        url = authorizer.get_authorization_url(base_url: OOB_URI)
        puts "Open the following URL in the browser and enter the "\
             "resulting code after authorization"
        puts url
        code = gets
        credentials = authorizer.get_and_store_credentials_from_code(
          user_id: CONFIGURATION["calendar"]["user_id"],
          code: code,
          base_url: OOB_URI
        )
      end
      credentials
    end

    def group_size
      CONFIGURATION["group_size"]
    end
  end
end
