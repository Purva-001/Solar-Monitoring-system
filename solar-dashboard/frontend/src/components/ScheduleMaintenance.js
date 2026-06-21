import React, { useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Chip,
  Grid,
  MenuItem,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  TextField,
  Typography
} from '@mui/material';
import { Build } from '@mui/icons-material';

const ScheduleMaintenance = ({ panelId = null, autoGenerateToken = 0, onComparisonOpen = null }) => {
  const panels = useMemo(
    () => [
      { id: 'PL01-B02-INV03-STR05-P01', label: 'PL01-B02-INV03-STR05-P01' },
      { id: 'PL01-B02-INV03-STR05-P02', label: 'PL01-B02-INV03-STR05-P02' },
      { id: 'PL01-B02-INV03-STR05-P03', label: 'PL01-B02-INV03-STR05-P03' }
    ],
    []
  );

  const [selectedPanelId, setSelectedPanelId] = useState(panelId || panels[0].id);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [result, setResult] = useState(null);
  const [lastAutoToken, setLastAutoToken] = useState(0);
  const [taskLoading, setTaskLoading] = useState(false);
  const [taskError, setTaskError] = useState(null);
  const [task, setTask] = useState({ technician: 'Kunal', status: 'PENDING', notes: '', suggested_work: '' });
  const [maintenanceTasks, setMaintenanceTasks] = useState([]);
  const [imageTimestamp, setImageTimestamp] = useState(new Date().getTime());

  const cameraUrl = process.env.REACT_APP_ESP32_CAMERA_URL || 'http://10.132.204.94:3001/uploads/latest.jpg';

  useEffect(() => {
    const id = setInterval(() => {
      setImageTimestamp(new Date().getTime());
    }, 2000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (panelId) setSelectedPanelId(panelId);
  }, [panelId]);

  useEffect(() => {
    if (!autoGenerateToken) return;
    if (loading) return;
    if (autoGenerateToken === lastAutoToken) return;
    // Ensure we generate for the panel coming from Health Report navigation.
    const pid = panelId || selectedPanelId;
    if (panelId && panelId !== selectedPanelId) return;
    setLastAutoToken(autoGenerateToken);
    handleGenerate(pid);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoGenerateToken, loading, lastAutoToken, panelId, selectedPanelId]);

  const _autoSaveSuggestedWork = async ({ panelIdToSave, maintenancePlanMd }) => {
    const md = String(maintenancePlanMd || '').trim();
    if (!md) return;
    try {
      await fetch(`/api/panel/task?panel_id=${encodeURIComponent(panelIdToSave)}`, {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          panel_id: panelIdToSave,
          technician: task.technician,
          status: task.status || 'PENDING',
          notes: task.notes,
          suggested_work: md,
        }),
      });
    } catch {
      // ignore auto-save failures; user can still manually Save
    }
  };

  const derivedTaskRow = useMemo(() => {
    const defect = String(result?.defect_analysis?.defect || '').trim();
    const defectLower = defect.toLowerCase();
    const fault = defect || (result ? 'Unknown' : '—');
    const action = defectLower.includes('soil') || defectLower.includes('dust') || defectLower.includes('hotspot')
      ? 'Clean'
      : defect ? 'Inspect' : '—';

    const confidencePct = (Number(result?.defect_analysis?.confidence) || 0) * 100;
    const priority = confidencePct >= 90 ? 'High' : confidencePct >= 70 ? 'Medium' : defect ? 'Low' : '—';
    const assignedTo = (task.technician || '').trim() || 'Kunal';
    const statusLabel = task.status === 'IN_PROGRESS' ? 'In Progress' : task.status === 'DONE' ? 'Done' : 'Pending';

    return {
      panelId: selectedPanelId,
      fault,
      action,
      priority,
      assignedTo,
      status: statusLabel,
    };
  }, [result, selectedPanelId, task.technician, task.status]);

  const [defectStatus, setDefectStatus] = useState({ electrical: 'PENDING', crack: 'PENDING' });

  useEffect(() => {
    try {
      const raw = localStorage.getItem(`defectStatus::${selectedPanelId}`);
      if (!raw) {
        setDefectStatus({ electrical: 'PENDING', crack: 'PENDING' });
        return;
      }
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object') {
        setDefectStatus({
          electrical: String(parsed.electrical || 'PENDING'),
          crack: String(parsed.crack || 'PENDING'),
        });
      }
    } catch {
      setDefectStatus({ electrical: 'PENDING', crack: 'PENDING' });
    }
  }, [selectedPanelId]);

  useEffect(() => {
    let cancelled = false;

    const fetchTasks = async () => {
      try {
        const res = await fetch('/api/tasks', { method: 'GET' });
        if (!res.ok) throw new Error(`Tasks request failed: ${res.status}`);
        const data = await res.json();
        if (cancelled) return;
        setMaintenanceTasks(Array.isArray(data) ? data : []);
      } catch {
        if (cancelled) return;
        setMaintenanceTasks([]);
      }
    };

    fetchTasks();
    return () => {
      cancelled = true;
    };
  }, [selectedPanelId, result?.timestamp]);

  const cachedPanelPowerW = useMemo(() => {
    try {
      const raw = localStorage.getItem(`panelPowerW::${selectedPanelId}`);
      const n = Number(raw);
      return Number.isFinite(n) ? n : null;
    } catch {
      return null;
    }
  }, [selectedPanelId]);

  const updateDefectStatus = async (key, nextStatus) => {
    const next = { ...defectStatus, [key]: nextStatus };
    setDefectStatus(next);
    try {
      localStorage.setItem(`defectStatus::${selectedPanelId}`, JSON.stringify(next));
    } catch {
      // ignore
    }

    // Best-effort sync: also store in task.notes so backend can persist when available.
    try {
      const notes = `Defect statuses: electrical=${next.electrical}, crack=${next.crack}`;
      await fetch(`/api/panel/task?panel_id=${encodeURIComponent(selectedPanelId)}`, {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          panel_id: selectedPanelId,
          technician: (task.technician || 'Kunal').trim() || 'Kunal',
          status: task.status || 'PENDING',
          notes,
          suggested_work: String(result?.maintenance_plan || '').trim(),
        }),
      });
    } catch {
      // ignore; backend may be down
    }
  };

  const defectMaintenanceRows = useMemo(
    () => {
      const basePower = Number.isFinite(cachedPanelPowerW) ? Number(cachedPanelPowerW) : 0;

      const parseDefectFromNotes = (notes) => {
        const s = String(notes || '');
        const m = s.match(/defect\s*:\s*([^\n\r]+)/i);
        return (m && m[1] ? String(m[1]).trim() : '').replace(/[\-_]+/g, ' ');
      };

      const formatDate = (iso) => {
        const d = iso ? new Date(iso) : null;
        if (!d || Number.isNaN(d.getTime())) return '—';
        return d.toLocaleDateString(undefined, { day: '2-digit', month: 'short', timeZone: 'UTC' });
      };

      const tasksForPanel = (Array.isArray(maintenanceTasks) ? maintenanceTasks : []).filter(
        (t) => String(t?.panel_id || '').trim() === String(selectedPanelId || '').trim()
      );

      const backendRows = tasksForPanel.map((t, idx) => {
        const defect = parseDefectFromNotes(t?.notes) || 'Maintenance';
        const backendStatus = String(t?.status || '').trim();
        const effectiveStatus = String(
          String(t?.panel_id || '') === String(selectedPanelId || '')
            ? (task.status || backendStatus || 'PENDING')
            : (backendStatus || 'PENDING')
        );
        return {
          id: `TASK-${t?.panel_id || selectedPanelId}-${idx}`,
          date: formatDate(t?.updated_at),
          defect,
          powerW: Math.max(0, basePower - 10),
          action: 'Inspect',
          technician: String(t?.technician || (task.technician || 'Kunal')).trim() || 'Kunal',
          resolutionStatus: effectiveStatus,
          showImage: false,
          isBackendTask: true,
        };
      });

      return [
      ...backendRows,
      {
        id: 'DEF-0002',
        date: '03 May',
        defect: 'Electrical Damage',
        powerW: Math.max(0, basePower - 8),
        action: 'Inspect',
        technician: (task.technician || 'Kunal').trim() || 'Kunal',
        resolutionStatus: defectStatus.electrical,
        showImage: false,
        statusKey: 'electrical',
        isBackendTask: false,
      },
      {
        id: 'DEF-0003',
        date: '01 May',
        defect: 'Crack',
        powerW: Math.max(0, basePower - 12),
        action: 'Inspect',
        technician: (task.technician || 'Kunal').trim() || 'Kunal',
        resolutionStatus: defectStatus.crack,
        showImage: false,
        statusKey: 'crack',
        isBackendTask: false,
      },
      ];
    },
    [cachedPanelPowerW, defectStatus.crack, defectStatus.electrical, maintenanceTasks, selectedPanelId, task.status, task.technician]
  );

  const handleGenerate = async (panelIdOverride = null) => {
    try {
      setLoading(true);
      setError(null);
      setResult(null);

      const pid = panelIdOverride || selectedPanelId;

      // If a previous task was completed, a newly generated plan should start as PENDING again.
      if (task.status === 'DONE') {
        const nextTask = { ...task, technician: (task.technician || 'Kunal').trim() || 'Kunal', status: 'PENDING' };
        setTask(nextTask);
        try {
          await saveTask(nextTask);
        } catch {
          // ignore; UI will still show pending
        }
      }

      const res = await fetch(`/api/panel/maintenance-plan?panel_id=${encodeURIComponent(pid)}`, {
        method: 'POST'
      });
      if (!res.ok) {
        const text = await res.text();
        throw new Error(text || `Request failed: ${res.status}`);
      }
      const data = await res.json();
      setResult(data);
      try {
        localStorage.setItem(`maintenancePlan::${pid}`, JSON.stringify(data));
      } catch {
        // ignore
      }

      // Auto-create/update work assignment payload once the plan exists.
      await _autoSaveSuggestedWork({ panelIdToSave: pid, maintenancePlanMd: data?.maintenance_plan });
    } catch (e) {
      setError(e?.message || 'Failed to generate maintenance plan');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    try {
      const raw = localStorage.getItem(`maintenancePlan::${selectedPanelId}`);
      if (!raw) return;
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object') {
        setResult(parsed);
      }
    } catch {
      // ignore
    }
  }, [selectedPanelId]);

  useEffect(() => {
    let cancelled = false;

    const fetchTask = async () => {
      try {
        setTaskError(null);
        setTaskLoading(true);
        const res = await fetch(`/api/panel/task?panel_id=${encodeURIComponent(selectedPanelId)}`, { method: 'GET' });
        if (!res.ok) throw new Error(`Task request failed: ${res.status}`);
        const data = await res.json();
        if (cancelled) return;
        setTask({
          technician: String(data?.technician || 'Kunal'),
          status: String(data?.status || 'PENDING'),
          notes: String(data?.notes || ''),
          suggested_work: String(data?.suggested_work || ''),
        });
      } catch (e) {
        if (cancelled) return;
        setTaskError(e?.message || 'Failed to fetch technician assignment');
        setTask({ technician: 'Kunal', status: 'PENDING', notes: '', suggested_work: '' });
      } finally {
        if (cancelled) return;
        setTaskLoading(false);
      }
    };

    if (selectedPanelId) fetchTask();
    return () => {
      cancelled = true;
    };
  }, [selectedPanelId]);

  const saveTask = async (overrideTask = null) => {
    try {
      setTaskError(null);
      setTaskLoading(true);
      const suggestedWork = String(result?.maintenance_plan || '').trim();

      const taskToSave = overrideTask || task;

      const res = await fetch(`/api/panel/task?panel_id=${encodeURIComponent(selectedPanelId)}`, {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          panel_id: selectedPanelId,
          technician: taskToSave.technician,
          status: taskToSave.status,
          notes: taskToSave.notes,
          suggested_work: suggestedWork,
        }),
      });
      if (!res.ok) throw new Error(`Task save failed: ${res.status}`);
      const data = await res.json();
      setTask({
        technician: String(data?.technician || 'Kunal'),
        status: String(data?.status || 'PENDING'),
        notes: String(data?.notes || ''),
        suggested_work: String(data?.suggested_work || ''),
      });
    } catch (e) {
      setTaskError(e?.message || 'Failed to save technician assignment');
    } finally {
      setTaskLoading(false);
    }
  };

  const handleStatusChange = async (nextStatus) => {
    const prevStatus = task.status;
    const nextTask = { ...task, technician: (task.technician || 'Kunal').trim() || 'Kunal', status: nextStatus };
    setTask(nextTask);
    await saveTask(nextTask);

    setMaintenanceTasks((prev) => {
      const items = Array.isArray(prev) ? prev : [];
      return items.map((t) => {
        if (String(t?.panel_id || '') !== String(selectedPanelId || '')) return t;
        return { ...t, status: nextStatus, technician: nextTask.technician, updated_at: new Date().toISOString() };
      });
    });

    if (String(prevStatus) !== 'DONE' && String(nextStatus) === 'DONE') {
      try {
        await fetch(`/api/panel/comparison/before?panel_id=${encodeURIComponent(selectedPanelId)}`, { method: 'POST' });
      } catch {
        // ignore; comparison page will handle missing before snapshot gracefully
      }

      if (typeof onComparisonOpen === 'function') {
        onComparisonOpen(selectedPanelId);
      }
    }
  };

  return (
    <Box>
      <Box
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: { xs: 'flex-start', md: 'center' },
          gap: 2,
          flexDirection: { xs: 'column', md: 'row' },
          mb: 2
        }}
      >
        <Box>
          <Typography variant="h4" fontWeight={900} sx={{ mb: 0.5 }}>
            Schedule Maintenance
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
            <Chip
              icon={<Build />}
              label={`Panel: ${selectedPanelId}`}
              sx={{ bgcolor: '#dcfce7', color: '#166534', fontWeight: 900 }}
            />
          </Box>
        </Box>

      </Box>

      {error && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}

      {result?.gemini_error && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          {String(result.gemini_error)}
        </Alert>
      )}

      <Grid container spacing={2.5}>
        <Grid item xs={12}>
          <Paper elevation={0} sx={{ p: 2.5, borderRadius: 2, border: '1px solid #eaeaea' }}>
            <Box sx={{ display: 'flex', alignItems: { xs: 'stretch', md: 'center' }, justifyContent: 'space-between', gap: 2, flexDirection: { xs: 'column', md: 'row' }, mb: 2 }}>
              <Typography fontWeight={900} sx={{ fontSize: 22 }}>
                Maintenance Task
              </Typography>

              <TextField
                select
                label="Panel"
                value={selectedPanelId}
                onChange={(e) => setSelectedPanelId(e.target.value)}
                sx={{ minWidth: { xs: '100%', md: 340 } }}
              >
                {panels.map((p) => (
                  <MenuItem key={p.id} value={p.id}>
                    {p.label}
                  </MenuItem>
                ))}
              </TextField>
            </Box>

            {taskError && (
              <Alert severity="warning" sx={{ mb: 2 }}>
                {taskError}
              </Alert>
            )}

            {!result ? (
              <Typography variant="body2" color="text.secondary" sx={{ fontSize: 16, fontWeight: 700 }}>
                Maintenance task will appear here when available.
              </Typography>
            ) : (
              <Paper elevation={0} sx={{ borderRadius: 2, border: '1px solid #eaeaea', bgcolor: '#fff', overflow: 'hidden' }}>
                <Table size="small" sx={{ minWidth: 900 }}>
                  <TableHead>
                    <TableRow>
                      <TableCell sx={{ fontWeight: 900, fontSize: 16 }}>Sr. No</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 16 }}>Panel ID</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 16 }}>Fault</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 16 }}>Action</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 16 }}>Priority</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 16 }}>Assigned To</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 16 }}>Status</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    <TableRow>
                      <TableCell sx={{ fontSize: 16, fontWeight: 800 }}>1</TableCell>
                      <TableCell sx={{ fontSize: 16, fontWeight: 800 }}>{derivedTaskRow.panelId}</TableCell>
                      <TableCell sx={{ fontSize: 16, fontWeight: 800 }}>{derivedTaskRow.fault}</TableCell>
                      <TableCell sx={{ fontSize: 16, fontWeight: 800 }}>{derivedTaskRow.action}</TableCell>
                      <TableCell sx={{ fontSize: 16, fontWeight: 800 }}>{derivedTaskRow.priority}</TableCell>
                      <TableCell sx={{ fontSize: 16, fontWeight: 800 }}>{derivedTaskRow.assignedTo}</TableCell>
                      <TableCell sx={{ fontSize: 16, fontWeight: 800, minWidth: 180 }}>
                        <TextField
                          select
                          size="small"
                          value={task.status}
                          disabled={taskLoading}
                          onChange={(e) => handleStatusChange(e.target.value)}
                          sx={{ minWidth: 160 }}
                        >
                          <MenuItem value="PENDING">Pending</MenuItem>
                          <MenuItem value="IN_PROGRESS">In Progress</MenuItem>
                          <MenuItem value="DONE">Done</MenuItem>
                        </TextField>
                      </TableCell>
                    </TableRow>
                  </TableBody>
                </Table>
              </Paper>
            )}
          </Paper>
        </Grid>

        <Grid item xs={12}>
          <Paper elevation={0} sx={{ p: 2.75, borderRadius: 2, border: '1px solid #eaeaea' }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
              <Build sx={{ color: '#22c55e' }} />
              <Typography variant="h5" fontWeight={900}>
                Defect & Maintenance Timeline
              </Typography>
            </Box>

            <Typography variant="body1" color="text.secondary" sx={{ mb: 2, fontWeight: 900 }}>
              Timeline view
            </Typography>

            <Paper variant="outlined" sx={{ borderRadius: 2, overflow: 'hidden' }}>
              <Box sx={{ width: '100%', overflowX: 'auto' }}>
                <Table size="small" sx={{ minWidth: 880 }}>
                  <TableHead>
                    <TableRow sx={{ bgcolor: '#f8fafc' }}>
                      <TableCell sx={{ fontWeight: 900, fontSize: 17, whiteSpace: 'nowrap' }}>Date</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 17, whiteSpace: 'nowrap' }}>Defect</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 17, whiteSpace: 'nowrap' }}>Power (W)</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 17, whiteSpace: 'nowrap' }}>Action</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 17, whiteSpace: 'nowrap' }}>Evidence</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 17, whiteSpace: 'nowrap' }}>Technician</TableCell>
                      <TableCell sx={{ fontWeight: 900, fontSize: 17, whiteSpace: 'nowrap' }}>Status</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {defectMaintenanceRows.map((row) => (
                      <TableRow key={row.id}>
                        <TableCell sx={{ fontWeight: 900, fontSize: 16, whiteSpace: 'nowrap' }}>{row.date}</TableCell>
                        <TableCell sx={{ fontWeight: 900, fontSize: 16, whiteSpace: 'nowrap' }}>{row.defect}</TableCell>
                        <TableCell sx={{ fontWeight: 900, fontSize: 16, whiteSpace: 'nowrap' }}>{Number(row.powerW || 0).toFixed(1)}</TableCell>
                        <TableCell sx={{ fontWeight: 900, fontSize: 16, whiteSpace: 'nowrap' }}>{row.action}</TableCell>
                        <TableCell sx={{ whiteSpace: 'nowrap' }}>
                          {row.showImage ? (
                            <Box
                              component="img"
                              alt="Dust evidence"
                              src={`${cameraUrl}?t=${imageTimestamp}`}
                              sx={{
                                width: 120,
                                height: 72,
                                objectFit: 'cover',
                                borderRadius: 1.5,
                                border: '1px solid #e5e7eb',
                                bgcolor: '#0b1220',
                              }}
                            />
                          ) : (
                            <Chip
                              label="Technician required"
                              size="small"
                              sx={{ bgcolor: '#fef2f2', color: '#b91c1c', fontWeight: 900 }}
                            />
                          )}
                        </TableCell>
                        <TableCell sx={{ fontWeight: 900, fontSize: 16, whiteSpace: 'nowrap' }}>{row.technician}</TableCell>
                        <TableCell sx={{ whiteSpace: 'nowrap' }}>
                          <TextField
                            select
                            size="small"
                            value={row.resolutionStatus}
                            onChange={(e) => {
                              if (row.isBackendTask) {
                                handleStatusChange(e.target.value);
                                return;
                              }
                              updateDefectStatus(row.statusKey, e.target.value);
                            }}
                            sx={{ minWidth: 160 }}
                          >
                            <MenuItem value="PENDING">Pending</MenuItem>
                            <MenuItem value="IN_PROGRESS">In Progress</MenuItem>
                            <MenuItem value="DONE">Done</MenuItem>
                          </TextField>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </Box>
            </Paper>
          </Paper>
        </Grid>
      </Grid>
    </Box>
  );
};

export default ScheduleMaintenance;
