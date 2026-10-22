import numpy as np, wave, glob, sys
for f in sorted(glob.glob(sys.argv[1]+'/*.wav')):
    w=wave.open(f); a=np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).astype(float)
    a=a[len(a)//4:]
    sp=np.abs(np.fft.rfft(a*np.hanning(len(a)))); fr=np.fft.rfftfreq(len(a),1/44100)
    m=(fr>30)&(fr<2000); pk=fr[m][np.argmax(sp[m])]
    print(f.split('/')[-1], 'rms=%.0f peak=%.0f clip=%.3f%% dom=%.1fHz'%(np.sqrt((a**2).mean()), np.abs(a).max(), 100*(np.abs(a)>32000).mean(), pk))
