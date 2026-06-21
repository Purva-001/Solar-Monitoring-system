import React, { useMemo, useState, useEffect } from 'react';
import {
  AppBar,
  Avatar,
  Badge,
  Box,
  CssBaseline,
  Divider,
  Drawer,
  IconButton,
  InputBase,
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Toolbar,
  ThemeProvider,
  createTheme,
  Typography,
  Button
} from '@mui/material';
import {
  Bolt,
  Build,
  Dashboard as DashboardIcon,
  ErrorOutline,
  Insights,
  NotificationsNone,
  Search,
  QrCodeScanner
} from '@mui/icons-material';
import SolarPanelGrid from './components/SolarPanelGrid';
import DashboardHome from './components/DashboardHome';
import SolarHistory from './components/SolarHistory';
import HealthReport from './components/HealthReport';
import GEnaiAnalysis from './components/GEnaiAnalysis';
import ScheduleMaintenance from './components/ScheduleMaintenance';
import MaintenanceComparisonAnalysis from './components/MaintenanceComparisonAnalysis';
import QrScanner from './components/qrscanner';
import axios from 'axios';

const theme = createTheme({
  palette: {
    primary: {
      main: '#4fc3f7',
    },
    secondary: {
      main: '#0288d1',
    },
    background: {
      default: '#e3f2fd',
      paper: '#f7fbff',
    },
    success: {
      main: '#4CAF50',
    },
    error: {
      main: '#F44336',
    },
    warning: {
      main: '#FFC107',
    }
  },
  typography: {
    fontFamily: '"Segoe UI", "Roboto", "Oxygen", "Ubuntu", "Cantarell", sans-serif',
    fontSize: 20,
    fontWeightRegular: 600,
    fontWeightMedium: 700,
    fontWeightBold: 900,
    h1: {
      fontWeight: 900,
      fontSize: '3.0rem'
    },
    h2: {
      fontWeight: 900,
      fontSize: '2.6rem'
    },
    h3: {
      fontWeight: 900,
      fontSize: '2.25rem'
    },
    h4: {
      fontWeight: 900,
      fontSize: '1.9rem'
    },
    h5: {
      fontWeight: 900,
      fontSize: '1.55rem'
    },
    h6: {
      fontWeight: 800,
      letterSpacing: '0.4px',
      fontSize: '1.3rem'
    },
    body1: {
      fontSize: '1.22rem',
      fontWeight: 700
    },
    body2: {
      fontSize: '1.15rem',
      fontWeight: 700
    },
    caption: {
      fontSize: '1.05rem',
      fontWeight: 700
    },
    subtitle1: {
      fontWeight: 900
    },
    subtitle2: {
      fontWeight: 800
    },
    button: {
      fontWeight: 900
    }
  },
  components: {
    MuiCssBaseline: {
      styleOverrides: {
        body: {
          fontWeight: 700
        },
        '*': {
          textRendering: 'geometricPrecision',
          WebkitFontSmoothing: 'antialiased',
          MozOsxFontSmoothing: 'grayscale'
        }
      }
    },
    MuiButton: {
      styleOverrides: {
        root: {
          fontSize: '1.12rem',
          fontWeight: 900,
          paddingTop: 10,
          paddingBottom: 10,
          paddingLeft: 18,
          paddingRight: 18
        }
      }
    },
    MuiInputBase: {
      styleOverrides: {
        root: {
          fontSize: '1.12rem',
          fontWeight: 750
        }
      }
    },
    MuiTableCell: {
      styleOverrides: {
        root: {
          fontSize: '1.12rem',
          paddingTop: 12,
          paddingBottom: 12
        }
      }
    },
    MuiChip: {
      styleOverrides: {
        label: {
          fontSize: '1.05rem',
          fontWeight: 900
        }
      }
    },
    MuiListItemText: {
      styleOverrides: {
        primary: {
          fontSize: '1.15rem',
          fontWeight: 900
        },
        secondary: {
          fontSize: '1.05rem',
          fontWeight: 700
        }
      }
    },
    MuiSvgIcon: {
      styleOverrides: {
        root: {
          fontSize: '1.6rem'
        }
      }
    }
  }
});

function App() {
  const [panelInfo, setPanelInfo] = useState(null);
  const [activePage, setActivePage] = useState('dashboard');
  const [mountedPages, setMountedPages] = useState({ dashboard: true });
  const [selectedPanel, setSelectedPanel] = useState(null);
  const [maintenanceAutoGenerateToken, setMaintenanceAutoGenerateToken] = useState(0);
  const [comparisonAutoRunToken, setComparisonAutoRunToken] = useState(0);

  const navItems = [
    { id: 'dashboard', label: 'Dashboard', icon: <DashboardIcon /> },
    { id: 'solar-history', label: 'Solar History', icon: <Insights /> },
    { id: 'health-report', label: 'Health Report', icon: <ErrorOutline /> },
    { id: 'genai-analysis', label: 'GenAI analysis', icon: <Insights /> },
    { id: 'qr-scanner', label: 'QR Scanner', icon: <QrCodeScanner /> },
    { id: 'maintenance', label: 'Maintenance', icon: <Build /> },
    { id: 'maintenance-comparison', label: 'Maintenance Comparison', icon: <Insights /> }
  ];

  const allowedPages = useMemo(() => new Set(navItems.map((n) => n.id)), [navItems]);

  useEffect(() => {
    // Restore state from URL
    try {
      const params = new URLSearchParams(window.location.search);
      const page = params.get('page');
      const panel = params.get('panel');
      if (page && allowedPages.has(page)) setActivePage(page);
      if (panel) setSelectedPanel({ id: panel });
    } catch {
      // ignore
    }

    // Fetch initial panel info
    fetchPanelInfo();
    
    // Set up auto-refresh
    const interval = setInterval(() => {
      fetchPanelInfo();
    }, 5000); // Update every 5 seconds

    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    // Persist state in URL
    try {
      const params = new URLSearchParams(window.location.search);
      params.set('page', activePage);
      if (selectedPanel?.id) {
        params.set('panel', selectedPanel.id);
      } else {
        params.delete('panel');
      }
      const nextUrl = `${window.location.pathname}?${params.toString()}`;
      window.history.replaceState(null, '', nextUrl);
    } catch {
      // ignore
    }
  }, [activePage, selectedPanel]);

  useEffect(() => {
    setMountedPages((prev) => {
      if (prev[activePage]) return prev;
      return { ...prev, [activePage]: true };
    });
  }, [activePage]);

  const fetchPanelInfo = async () => {
    try {
      const response = await axios.get(
        `/api/panel/info?panelId=PL01-B02-INV03-STR05-P01`,
        { timeout: 5000 }
      );
      setPanelInfo(response.data);
      console.log(" Panel info:", response.data);
    } catch (error) {
      console.error(" Error fetching panel info:", error);
    }
  };

  const drawerWidth = 260;

  const handlePanelSelect = (panel) => {
    setSelectedPanel(panel);
    setActivePage('dashboard');
  };

  const handleOpenHealthReport = (panel) => {
    setSelectedPanel(panel);
    setActivePage('health-report');
  };

  const handleOpenScheduleMaintenance = (panelOrId = null) => {
    const panel = typeof panelOrId === 'string' ? { id: panelOrId } : panelOrId;
    setSelectedPanel(panel);
    setActivePage('maintenance');
  };

  const handleOpenScheduleMaintenanceAuto = (panelOrId = null) => {
    const panel = typeof panelOrId === 'string' ? { id: panelOrId } : panelOrId;
    setSelectedPanel(panel);
    setMaintenanceAutoGenerateToken((t) => t + 1);
    setActivePage('maintenance');
  };

  const handleOpenMaintenanceComparison = (panelOrId = null) => {
    const panel = typeof panelOrId === 'string' ? { id: panelOrId } : panelOrId;
    setSelectedPanel(panel);
    setComparisonAutoRunToken((t) => t + 1);
    setActivePage('maintenance-comparison');
  };

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <>
          <AppBar
            position="fixed"
            elevation={3}
            sx={{
              background: (t) => `linear-gradient(135deg, ${t.palette.primary.main} 0%, ${t.palette.primary.dark} 100%)`,
              zIndex: (t) => t.zIndex.drawer + 1,
              ml: { sm: `${drawerWidth}px` },
              width: { sm: `calc(100% - ${drawerWidth}px)` }
            }}
          >
            <Toolbar sx={{ py: 1.25, gap: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <Bolt sx={{ fontSize: 32, color: '#e1f5fe' }} />
                <Typography variant="h6" component="div" sx={{ fontWeight: 800, letterSpacing: '0.4px' }}>
                  SolarMonitor Pro
                </Typography>
              </Box>

              <Box
                sx={{
                  flexGrow: 1,
                  display: { xs: 'none', md: 'flex' },
                  alignItems: 'center',
                  gap: 1,
                  px: 1.5,
                  py: 0.75,
                  borderRadius: 2,
                  bgcolor: 'rgba(255,255,255,0.18)',
                  border: '1px solid rgba(255,255,255,0.25)'
                }}
              >
                <Search sx={{ opacity: 0.9 }} />
                <InputBase
                  placeholder="Search metrics or panels..."
                  sx={{ color: 'white', width: '100%' }}
                  inputProps={{ 'aria-label': 'search' }}
                />
              </Box>

              <IconButton color="inherit" sx={{ display: { xs: 'none', sm: 'inline-flex' } }}>
                <Badge color="error" variant="dot">
                  <NotificationsNone />
                </Badge>
              </IconButton>

              {panelInfo?.panel_id && (
                <Typography
                  variant="body2"
                  sx={{
                    px: 1.25,
                    py: 0.5,
                    borderRadius: 2,
                    bgcolor: 'rgba(255,255,255,0.18)',
                    border: '1px solid rgba(255,255,255,0.25)'
                  }}
                >
                  Panel: {panelInfo.panel_id}
                </Typography>
              )}

              <Avatar sx={{ width: 34, height: 34, bgcolor: 'rgba(0,0,0,0.25)' }}>
                A
              </Avatar>
            </Toolbar>
          </AppBar>

          <Box sx={{ display: 'flex' }}>
            <Drawer
              variant="permanent"
              sx={{
                width: drawerWidth,
                flexShrink: 0,
                display: { xs: 'none', sm: 'block' },
                '& .MuiDrawer-paper': {
                  width: drawerWidth,
                  boxSizing: 'border-box',
                  borderRight: '1px solid #e6e6e6',
                  bgcolor: 'background.paper'
                }
              }}
              open
            >
              <Toolbar />
              <Box sx={{ px: 2.5, pt: 2, pb: 1.5 }}>
                <Typography variant="subtitle1" fontWeight={900}>
                  Solar Plant Admin
                </Typography>
                <Typography variant="caption" color="text.secondary">
                  Site ID: PV-7742
                </Typography>
              </Box>
              <Divider />
              <List sx={{ px: 1.25, py: 1 }}>
                {navItems.map((item) => (
                  <ListItemButton
                    key={item.id}
                    selected={activePage === item.id}
                    onClick={() => setActivePage(item.id)}
                    sx={{
                      borderRadius: 2,
                      mb: 0.75,
                      '&.Mui-selected': {
                        bgcolor: 'rgba(79, 195, 247, 0.25)',
                        '&:hover': { bgcolor: 'rgba(79, 195, 247, 0.35)' }
                      }
                    }}
                  >
                    <ListItemIcon sx={{ minWidth: 40 }}>{item.icon}</ListItemIcon>
                    <ListItemText primary={item.label} />
                  </ListItemButton>
                ))}
              </List>
            </Drawer>

            <Box
              component="main"
              sx={{
                flexGrow: 1,
                width: { sm: `calc(100% - ${drawerWidth}px)` },
                bgcolor: 'background.default',
                minHeight: '100vh'
              }}
            >
              <Toolbar />
              <Box sx={{ px: { xs: 2, md: 3 }, py: 3 }}>
                {mountedPages.dashboard && (
                  <Box sx={{ display: activePage === 'dashboard' ? 'block' : 'none' }}>
                    <DashboardHome />
                    <SolarPanelGrid onPanelSelect={handlePanelSelect} onHealthReportOpen={handleOpenHealthReport} />
                  </Box>
                )}

                {mountedPages['solar-history'] && (
                  <Box sx={{ display: activePage === 'solar-history' ? 'block' : 'none' }}>
                    <SolarHistory assetId="SolarPanel_01" isActive={activePage === 'solar-history'} />
                  </Box>
                )}

                {mountedPages['health-report'] && (
                  <Box sx={{ display: activePage === 'health-report' ? 'block' : 'none' }}>
                    <HealthReport
                      panelId={selectedPanel?.id || null}
                      onScheduleMaintenanceOpen={handleOpenScheduleMaintenanceAuto}
                    />
                  </Box>
                )}

                {mountedPages['genai-analysis'] && (
                  <Box sx={{ display: activePage === 'genai-analysis' ? 'block' : 'none' }}>
                    <GEnaiAnalysis
                      panelId={selectedPanel?.id || panelInfo?.panel_id || null}
                      onScheduleMaintenanceOpen={handleOpenScheduleMaintenanceAuto}
                    />
                  </Box>
                )}

                {activePage === 'qr-scanner' && (
                  <Box sx={{ mx: -3, mt: -3 }}>
                    <QrScanner onOpenReport={handleOpenHealthReport} />
                  </Box>
                )}

                {mountedPages.maintenance && (
                  <Box sx={{ display: activePage === 'maintenance' ? 'block' : 'none' }}>
                    <ScheduleMaintenance
                      panelId={selectedPanel?.id || null}
                      autoGenerateToken={maintenanceAutoGenerateToken}
                      onComparisonOpen={handleOpenMaintenanceComparison}
                    />
                  </Box>
                )}

                {mountedPages['maintenance-comparison'] && (
                  <Box sx={{ display: activePage === 'maintenance-comparison' ? 'block' : 'none' }}>
                    <MaintenanceComparisonAnalysis
                      panelId={selectedPanel?.id || panelInfo?.panel_id || null}
                      autoRunToken={comparisonAutoRunToken}
                    />
                  </Box>
                )}

                {mountedPages[activePage] !== true && (
                  <SolarPanelGrid onPanelSelect={handlePanelSelect} onHealthReportOpen={handleOpenHealthReport} />
                )}
              </Box>
            </Box>
          </Box>
      </>
    </ThemeProvider>
  );
}

export default App;

