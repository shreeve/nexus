if a > 1
  puts "big"
elsif a == 1
  puts "one"
else
  puts "small"
end
unless done
  work
end
while i < 10
  i += 1
end
until queue.empty?
  queue.pop
end
for x in [1, 2, 3]
  total += x
end
case value
when 1, 2 then :low
when 3..5
  :mid
else
  :high
end
x = 1 if ready
y = 2 unless failed
