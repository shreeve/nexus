ls -la | grep foo | wc -l
echo hello > out.txt
cat < in.txt >> log.txt 2>&1
make && make test || echo failed
sleep 10 &
