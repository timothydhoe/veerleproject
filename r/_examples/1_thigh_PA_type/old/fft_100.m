function [amp,loc]=fft_100(data)

Fs=100;
T_t=1/Fs;
L_l=length(data);
Y_y = fft(data);
P2 = abs(Y_y/L_l);
P1 = P2(1:floor(L_l/2)+1,:);
P1(2:end-1,:) = 2*P1(2:end-1,:);
f_f = Fs*(0:floor(L_l/2))/L_l;
[amp,loc]=max(P1);
loc=f_f(loc);

