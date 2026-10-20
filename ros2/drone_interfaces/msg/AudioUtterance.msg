# Bas-konus ile alinmis tek bir konusma (mobile_bridge -> stt_node, Faz 3).
# Ses telefonda 16 kHz mono PCM16 olarak yakalanir.

builtin_interfaces/Time t_konusma_basladi
builtin_interfaces/Time t_konusma_bitti   # PTT birakildi (kopruye ulasma ani)
uint32 id                                 # telefondaki konusma kimligi
string kaynak                             # telefon | mikrofon | dosya
uint32 ornekleme_hz                       # 16000
int16[] ornekler                          # mono PCM
