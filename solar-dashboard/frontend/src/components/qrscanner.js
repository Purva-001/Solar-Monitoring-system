import React, { useEffect, useState, useRef } from 'react';
import { Box, Typography, Button, IconButton } from '@mui/material';
import { QrCodeScanner, FlashOn, Cameraswitch, ErrorOutline, Bolt, ElectricBolt } from '@mui/icons-material';
import { Html5Qrcode } from 'html5-qrcode';

// --- Parsing Logic ported from Dart ---

function currentToAmps(raw) {
  const x = Math.abs(raw);
  const v = Number(raw);
  return x > 50 ? v / 1000.0 : v;
}

function parseQrPayload(raw) {
  const trimmed = String(raw).trim();
  if (!trimmed) return { lines: [], error: 'Empty QR payload.' };

  if (!isNaN(trimmed)) {
    return { headline: 'Reading', lines: [trimmed], error: null };
  }

  let decoded;
  try {
    decoded = JSON.parse(trimmed);
  } catch (e) {
    return { lines: [], error: 'Payload is not valid JSON.' };
  }

  if (Array.isArray(decoded) && decoded.length > 0 && typeof decoded[0] === 'object') {
    decoded = decoded[0];
  }

  if (typeof decoded !== 'object' || decoded === null) {
    return { lines: [], error: 'Expected a JSON object (or array of one object).' };
  }

  for (const key of ['sensor_value', 'sensorValue', 'value', 'reading', 'sensor']) {
    if (decoded[key] != null) {
      return { headline: 'Sensor', lines: [String(decoded[key])], error: null };
    }
  }

  const hasIv = ['I1', 'V1', 'I2', 'V2', 'I3', 'V3', 'I4', 'V4'].some(k => k in decoded);
  if (hasIv) {
    const lines = [];
    const channels = [];
    let firstPower = null;

    for (let i = 1; i <= 4; i++) {
      const ik = `I${i}`;
      const vk = `V${i}`;
      if (!(ik in decoded) && !(vk in decoded)) continue;

      const iv = decoded[ik];
      const vv = decoded[vk];
      if (iv == null || vv == null) continue;

      const iNum = Number(iv);
      const vNum = Number(vv);
      if (isNaN(iNum) || isNaN(vNum)) continue;

      const fromMa = Math.abs(iNum) > 50;
      const ia = currentToAmps(iNum);
      const vd = vNum;
      const p = ia * vd;
      if (i === 1) firstPower = p;

      channels.push({
        index: i,
        voltage: vd,
        currentAmps: ia,
        powerW: p,
        rawCurrent: iNum,
        fromMilliamps: fromMa
      });

      const iaLabel = ia.toFixed(3);
      const iLabel = fromMa ? `${iNum} mA → ${iaLabel} A` : `${iaLabel} A`;
      lines.push(`Channel ${i}: ${vd.toFixed(2)} V · ${iLabel}`);
      lines.push(`  Power ≈ ${p.toFixed(4)} W`);
    }

    if (lines.length === 0) {
      return { lines: [], error: 'IV keys present but could not read numeric I/V pairs.' };
    }

    const head = firstPower !== null 
      ? `Est. power (ch 1): ${firstPower.toFixed(4)} W`
      : 'Solar IV readings';

    return { headline: head, lines, error: null, ivChannels: channels };
  }

  return { lines: [], error: 'No known sensor fields (value / IV channels I1·V1 …) found.' };
}

function looksLikePanelId(s) {
  const t = String(s).trim();
  if (!t) return false;
  if (/^PANEL[_\-]?\d+$/i.test(t)) return true;
  if (/^PL01-B02-INV03-STR05-P0[1-4]$/i.test(t)) return true;
  return false;
}

function tryExtractPanelId(raw) {
  const s = String(raw).trim();
  if (!s) return null;

  try {
    let dec = JSON.parse(s);
    if (Array.isArray(dec) && dec.length > 0) dec = dec[0];
    if (typeof dec === 'object' && dec !== null) {
      const pid = dec.panel_id || dec.panelId || dec.id;
      if (pid) {
        const t = String(pid).trim();
        if (looksLikePanelId(t)) return t;
      }
    }
  } catch (e) {}

  if (looksLikePanelId(s)) return s;

  const match = s.match(/\b(PANEL[_\-]?\d+|PL01-B02-INV03-STR05-P0[1-4])\b/i);
  if (match) return match[1].replace(/ /g, '');
  return null;
}

// --- React Component ---

const QrScanner = ({ onOpenReport }) => {
  const [hasCameraPermission, setHasCameraPermission] = useState(null);
  const [rawPayload, setRawPayload] = useState(null);
  const [parsedData, setParsedData] = useState(null);
  const qrCodeScanner = useRef(null);
  const [cameraList, setCameraList] = useState([]);
  const [currentCameraIdx, setCurrentCameraIdx] = useState(0);

  useEffect(() => {
    let isMounted = true;
    let html5QrCode = null;
    
    const initScanner = async () => {
      try {
        const devices = await Html5Qrcode.getCameras();
        if (!isMounted) return;

        if (devices && devices.length > 0) {
          setHasCameraPermission(true);
          setCameraList(devices);

          html5QrCode = new Html5Qrcode("reader");
          qrCodeScanner.current = html5QrCode;
          
          await html5QrCode.start(
            devices[0].id,
            {
              fps: 20,
              // Removed qrbox and aspectRatio to allow scanning the entire screen 
              // without distorting the camera feed.
            },
            (decodedText) => {
              if (decodedText && decodedText.trim() !== '') {
                setRawPayload(decodedText);
                setParsedData(parseQrPayload(decodedText));
              }
            },
            (errorMessage) => {
              // ignore scan errors
            }
          );
        } else {
          if (isMounted) setHasCameraPermission(false);
        }
      } catch (err) {
        console.error("Error accessing cameras", err);
        if (isMounted) setHasCameraPermission(false);
      }
    };

    const timeoutId = setTimeout(() => {
      if (isMounted) initScanner();
    }, 150);

    return () => {
      isMounted = false;
      clearTimeout(timeoutId);
      if (html5QrCode) {
        try {
          if (html5QrCode.isScanning) {
            html5QrCode.stop().then(() => html5QrCode.clear()).catch(() => {});
          } else {
            html5QrCode.clear();
          }
        } catch (e) {}
      }
    };
  }, []);

  const startCamera = async (html5QrCode, deviceId) => {
    try {
      await html5QrCode.start(
        deviceId,
        {
          fps: 10,
          qrbox: { width: 250, height: 250 },
          aspectRatio: 1.0
        },
        (decodedText) => {
          if (decodedText && decodedText.trim() !== '') {
            setRawPayload(decodedText);
            setParsedData(parseQrPayload(decodedText));
          }
        },
        (errorMessage) => {
          // ignore scan errors
        }
      );
    } catch (err) {
      console.error("Error starting camera", err);
    }
  };

  const handleSwitchCamera = async () => {
    if (cameraList.length <= 1 || !qrCodeScanner.current) return;
    const nextIdx = (currentCameraIdx + 1) % cameraList.length;
    setCurrentCameraIdx(nextIdx);
    
    if (qrCodeScanner.current.isScanning) {
      await qrCodeScanner.current.stop();
    }
    await startCamera(qrCodeScanner.current, cameraList[nextIdx].id);
  };

  const panelIdGuess = tryExtractPanelId(rawPayload || '');

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', height: 'calc(100vh - 64px)', bgcolor: '#0C1222' }}>
      {/* Scanner Section */}
      <Box sx={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
        <Box id="reader" sx={{ width: '100%', height: '100%', '& video': { objectFit: 'cover' } }} />
        
        {/* Overlay gradient */}
        <Box sx={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 56, background: 'linear-gradient(to bottom, rgba(12,18,34,0), rgba(12,18,34,0.85))' }} />

        {/* Framing box */}
        <Box sx={{
          position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)',
          width: 350, height: 350, borderRadius: '18px', border: '2.5px solid rgba(255,255,255,0.9)',
          boxShadow: '0 0 24px 2px rgba(14, 165, 233, 0.25)', pointerEvents: 'none'
        }} />

        {/* Top Actions */}
        <Box sx={{ position: 'absolute', top: 12, left: 12, right: 12, display: 'flex', justifyContent: 'space-between' }}>
          <IconButton onClick={() => {/* Torch toggling logic if supported */}} sx={{ bgcolor: 'rgba(0,0,0,0.45)', color: 'white', '&:hover': { bgcolor: 'rgba(0,0,0,0.6)' } }}>
            <FlashOn fontSize="small" />
          </IconButton>
          <IconButton onClick={handleSwitchCamera} sx={{ bgcolor: 'rgba(0,0,0,0.45)', color: 'white', '&:hover': { bgcolor: 'rgba(0,0,0,0.6)' } }}>
            <Cameraswitch fontSize="small" />
          </IconButton>
        </Box>

        {/* Hint text */}
        <Box sx={{ position: 'absolute', top: 60, left: 0, right: 0, display: 'flex', justifyContent: 'center' }}>
          <Box sx={{ px: 2, py: 1, bgcolor: 'rgba(0,0,0,0.55)', borderRadius: '20px', border: '1px solid rgba(255,255,255,0.12)' }}>
            <Typography sx={{ color: 'white', fontWeight: 700, fontSize: '0.85rem', letterSpacing: 0.2 }}>
              Align the QR code inside the frame
            </Typography>
          </Box>
        </Box>
      </Box>

      {/* Result Panel */}
      <Box sx={{ 
        flex: 1, 
        bgcolor: '#F8FAFC', 
        borderTopLeftRadius: 22, 
        borderTopRightRadius: 22, 
        boxShadow: '0 -6px 16px rgba(0,0,0,0.12)',
        display: 'flex', flexDirection: 'column',
        overflow: 'hidden'
      }}>
        <Box sx={{ pt: 1.5, pb: 1, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          <Box sx={{ width: 40, height: 4, bgcolor: '#9CA3AF', borderRadius: 99, mb: 1 }} />
          <Typography sx={{ fontWeight: 800, fontSize: '0.8rem', color: '#4B5563', letterSpacing: 0.4 }}>
            Scan result
          </Typography>
        </Box>

        <Box sx={{ flex: 1, overflowY: 'auto', px: 2, pb: 2 }}>
          {!rawPayload ? (
            <Box sx={{ height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
              <QrCodeScanner sx={{ fontSize: 48, color: 'rgba(22, 163, 74, 0.75)', mb: 1.5 }} />
              <Typography sx={{ fontWeight: 900, fontSize: '1.1rem', color: '#111827', mb: 1 }}>Health report</Typography>
              <Typography sx={{ color: '#4B5563', fontWeight: 600, fontSize: '0.85rem', mb: 2 }}>Scan a panel QR code to open the full report.</Typography>
              
              <Box sx={{ bgcolor: 'white', borderRadius: 2, border: '1px solid #E2E8F0', p: 1.5, boxShadow: '0 2px 6px rgba(0,0,0,0.04)' }}>
                <Typography sx={{ fontFamily: 'monospace', fontSize: '0.8rem', fontWeight: 700, color: '#1E293B', whiteSpace: 'pre-line' }}>
                  PANEL_001{'\n'}or{'\n'}{'{"I1": 122, "V1": 0.16}'}
                </Typography>
              </Box>
            </Box>
          ) : (
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              {panelIdGuess && (
                <Box sx={{ textAlign: 'center' }}>
                  <Button 
                    variant="contained" 
                    fullWidth 
                    size="large"
                    onClick={() => onOpenReport({ id: panelIdGuess })}
                    startIcon={<ErrorOutline />}
                    sx={{ borderRadius: 3, fontWeight: 900, py: 1.5, mb: 1.5 }}
                  >
                    OPEN FULL HEALTH REPORT
                  </Button>
                  <Typography sx={{ fontWeight: 900, fontSize: '0.85rem', color: '#374151' }}>
                    Panel id: {panelIdGuess}
                  </Typography>
                </Box>
              )}

              {parsedData?.headline && (
                <Typography sx={{ fontWeight: 900, fontSize: '1.1rem', color: '#0F172A' }}>
                  {parsedData.headline}
                </Typography>
              )}

              {parsedData?.error && (
                <Box sx={{ bgcolor: '#FFF1F2', p: 1.5, borderRadius: 2, border: '1px solid #FECACA', display: 'flex', gap: 1 }}>
                  <ErrorOutline sx={{ color: '#B91C1C', fontSize: 22 }} />
                  <Typography sx={{ color: '#7F1D1D', fontWeight: 700, fontSize: '0.85rem' }}>{parsedData.error}</Typography>
                </Box>
              )}

              {parsedData?.ivChannels?.map((c) => (
                <Box key={c.index} sx={{ bgcolor: 'white', p: 1.5, borderRadius: 2, border: '1px solid #E2E8F0', boxShadow: '0 2px 8px rgba(0,0,0,0.04)' }}>
                  <Typography sx={{ fontWeight: 900, fontSize: '0.85rem', color: '#374151', mb: 1.5 }}>
                    Channel {c.index}
                  </Typography>
                  <Box sx={{ display: 'flex', gap: 1, mb: 1 }}>
                    <Box sx={{ flex: 1, bgcolor: '#F1F5F9', p: 1.25, borderRadius: 1.5 }}>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 0.5 }}>
                        <Bolt sx={{ fontSize: 14, color: '#4B5563' }} />
                        <Typography sx={{ fontSize: '0.65rem', fontWeight: 800, color: '#4B5563' }}>VOLTAGE</Typography>
                      </Box>
                      <Typography sx={{ fontWeight: 800, fontSize: '0.8rem', color: '#0F172A' }}>{c.voltage.toFixed(2)} V</Typography>
                    </Box>
                    <Box sx={{ flex: 1, bgcolor: '#F1F5F9', p: 1.25, borderRadius: 1.5 }}>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mb: 0.5 }}>
                        <ElectricBolt sx={{ fontSize: 14, color: '#4B5563' }} />
                        <Typography sx={{ fontSize: '0.65rem', fontWeight: 800, color: '#4B5563' }}>CURRENT</Typography>
                      </Box>
                      <Typography sx={{ fontWeight: 800, fontSize: '0.8rem', color: '#0F172A' }}>
                        {c.fromMilliamps ? `${c.rawCurrent} mA (${c.currentAmps.toFixed(3)} A)` : `${c.currentAmps.toFixed(3)} A`}
                      </Typography>
                    </Box>
                  </Box>
                  <Box sx={{ bgcolor: '#E0F2FE', p: 1.25, borderRadius: 1.5, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <Typography sx={{ fontWeight: 800, fontSize: '0.75rem', color: '#334155' }}>Power (est.)</Typography>
                    <Typography sx={{ fontWeight: 900, fontSize: '0.95rem', color: '#0369A1' }}>{c.powerW.toFixed(4)} W</Typography>
                  </Box>
                </Box>
              ))}

              {(!parsedData?.ivChannels || parsedData.ivChannels.length === 0) && parsedData?.lines?.length > 0 && (
                <Box>
                  {parsedData.lines.map((line, i) => (
                    <Typography key={i} sx={{ color: '#334155', fontWeight: 600, fontSize: '0.85rem', mb: 0.5 }}>{line}</Typography>
                  ))}
                </Box>
              )}

              <Box sx={{ mt: 1 }}>
                <Typography sx={{ fontWeight: 800, fontSize: '0.75rem', color: '#4B5563', mb: 0.5 }}>Raw payload</Typography>
                <Box sx={{ bgcolor: 'white', p: 1.5, borderRadius: 2, border: '1px solid #E2E8F0', overflowX: 'auto' }}>
                  <Typography sx={{ color: '#1E293B', fontWeight: 500, fontSize: '0.75rem', fontFamily: 'monospace', whiteSpace: 'pre-wrap' }}>
                    {rawPayload}
                  </Typography>
                </Box>
              </Box>

            </Box>
          )}
        </Box>
      </Box>
    </Box>
  );
};

export default QrScanner;
