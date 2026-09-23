begin
  risky
rescue ArgumentError => e
  puts e.message
rescue
  retry
ensure
  cleanup
end
x = risky rescue 0
