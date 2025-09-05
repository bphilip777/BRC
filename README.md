# 1 billion row challenge:
I am very late to this party, but I thought I'd give it a shot since Casey Muratori's
video series on the topic came out.

# Aims: 
1. Create 1 billion rows as fast as possible 
2. Read and Update on 1 billion rows as fast as possible

# Versions:
## Create Measurements
### Version 0: 
- implements basic write operations
- uses std formatting
- writes after each newline

### Version 1:
- uses memset + memcpy
- uses buffered writes
- writes after each buffer is full

### Version 2:
- uses threads 
- precomputes random numbers to get file length + seeks 
- 

## Read Measurements

## Timer
### Version 0:
- simply times how long it takes to perform a task 1x
- has formatting to tell the sequence better

### Version 1:
- runs through each condition 3x 
- formats times for each 
- ranks outputs for each
