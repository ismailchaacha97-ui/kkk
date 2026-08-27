# Let's inspect the code for potential MT4 bugs
with open('MQL4/Indicators/VeteranTrader_Pro_V1.mq4') as f:
    code = f.read()

print("Checking potential runtime issues...")
