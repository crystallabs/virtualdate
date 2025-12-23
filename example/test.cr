require "../src/virtualdate"

yaml = "vdates.yml"
vdates = VirtualDate::VirtualDateFile.load(File.read("vdates.yml"))

scheduler = VirtualDate::Scheduler.new(vdates)

1.upto(10) do |i|
  from, to = Time.local(2023, 5, i, 0, 0, 0), Time.local(2023, 5, i, 23, 59, 59)

  instances = scheduler.build(from, to)

  puts "-------------------------------------"
  puts "Schedule for #{from.to_s("%F")} (#{from.day_of_week.to_s})"

  instances
    .sort_by(&.start)
    .each do |i|
      puts "%-10s  %s – %s  (%s)" % {
        i.start.to_s,
        i.finish.to_s,
        "\t",
        i.vdate.id,
        i.vdate.flags.join(", "),
      }

      puts "\t#{i.vdate.id} @ #{i.start}"
      puts "\t" + i.explanation.to_s
    end

  # This repeats, and only the last date is in the file
  ics = VirtualDate::ICS.export(
    instances,
    calendar_name: "My Task Schedule"
  )
  File.write("vdates.ics", ics)
end

file = {
  "schema_version" => VirtualDate::Migrator::CURRENT_VERSION,
  "vdates"         => vdates,
}

File.write("vdates.yml", file.to_yaml)
