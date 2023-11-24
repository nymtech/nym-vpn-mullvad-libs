use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    prelude::{Backend, Constraint, CrosstermBackend, Layout, Terminal},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, Cell, List, ListItem, ListState, Row, Table, TableState},
    Frame,
};
use std::io::{self, stdout, Result};
use test_manager_config::{ConfigFile, OsType, VmConfig, VmType, API};

#[allow(unused)]
struct App {
    state: TableState,
    env_state: ListState,
    items: Vec<VMInfo>,
    config: ConfigFile,
}

#[allow(dead_code, unused)]
fn main() -> Result<()> {
    // load `test-manager` config
    let mut config = {
        let config_path = dirs::config_dir()
            .expect("Config directory not found. Can not load VM config")
            .join("mullvad-test")
            .join("config.json");
        ConfigFile::load_or_default(config_path).expect("Failed to load config")
    };

    // Set up ratatui / terminal
    enable_raw_mode()?;
    let mut stdout = stdout();
    execute!(stdout, EnterAlternateScreen,)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Run application
    let app = App::new(config);
    let res = run_app(&mut terminal, app);

    // Restore terminal
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    Ok(())
}

fn run_app<B: Backend>(terminal: &mut Terminal<B>, mut app: App) -> io::Result<()> {
    loop {
        terminal.draw(|f| ui(f, &mut app))?;

        if event::poll(std::time::Duration::from_millis(16))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') => return Ok(()),
                        KeyCode::Down | KeyCode::Char('j') => app.next(),
                        KeyCode::Up | KeyCode::Char('k') => app.previous(),
                        // Fold or Unfold the currently selected item
                        KeyCode::Tab => {
                            app.on_tab();
                        }
                        _ => {}
                    }
                }
            }
        }
    }
}

fn ui(f: &mut Frame, app: &mut App) {
    let rects = Layout::default()
        .constraints([Constraint::Percentage(40), Constraint::Percentage(5)])
        .split(f.size());

    let selected_style = Style::default().add_modifier(Modifier::REVERSED);
    let normal_style = Style::default().bg(Color::Blue);
    let header_cells = ["Name", "VM-type", "OS"]
        .iter()
        .map(|h| Cell::from(*h).style(Style::default().fg(Color::Red)));
    let header = Row::new(header_cells)
        .style(normal_style)
        .height(1)
        .bottom_margin(1);
    let rows: Vec<Row> = app
        .items
        .iter()
        .cloned()
        .flat_map(Vec::<Row>::from)
        .collect();
    let t = Table::new(rows)
        .header(header)
        .block(Block::default().borders(Borders::ALL).title("VMs"))
        .highlight_style(selected_style)
        .highlight_symbol(">> ")
        .widths(&[
            Constraint::Percentage(50),
            Constraint::Max(30),
            Constraint::Min(10),
        ]);
    f.render_stateful_widget(t, rects[0], &mut app.state);

    let items: Vec<ListItem> = vec![
        ListItem::new(API::Production.to_string()).style(selected_style),
        ListItem::new(API::Staging.to_string()),
    ];

    // Create a List from all list items and highlight the currently selected one
    let items = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title("Test environments"),
        )
        .highlight_style(
            Style::default()
                .bg(Color::LightGreen)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol(">> ");

    // We can now render the item list
    f.render_stateful_widget(items, rects[1], &mut app.env_state);
}

impl App {
    fn new(config: ConfigFile) -> App {
        let items: Vec<VMInfo> = config
            .vms
            .iter()
            .map(|(vm, options)| VMInfo {
                name: vm.clone(),
                inner: options.clone(),
                folded: true,
            })
            .collect();
        let initial_state = TableState::default().with_selected(Some(0));
        App {
            state: initial_state,
            items,
            config,
            env_state: ListState::default(),
        }
    }
    pub fn next(&mut self) {
        let i = match self.state.selected() {
            Some(i) => {
                if i >= self.items.len() - 1 {
                    0
                } else {
                    i + 1
                }
            }
            None => 0,
        };
        self.state.select(Some(i));
    }

    pub fn previous(&mut self) {
        let i = match self.state.selected() {
            Some(i) => {
                if i == 0 {
                    self.items.len() - 1
                } else {
                    i - 1
                }
            }
            None => 0,
        };
        self.state.select(Some(i));
    }

    pub fn on_tab(&mut self) {
        // Currently selected row
        let index = match self.state.selected() {
            Some(index) => index,
            None => {
                // This *should* be logged: Row index is out of bounds, probably due to a bug in
                // `next` or `previous`.
                return;
            }
        };
        let item = match self.items.get_mut(index) {
            Some(item) => item,
            None => {
                // This *should* be logged: Row index does not point at a VM config, probably due to
                // a bug in `next` or `previous`.
                return;
            }
        };
        item.folded = !item.folded;
    }
}

/// The item representing a virtual machine configuration which is rendered in
/// the TUI.
#[derive(Debug, Clone)]
pub struct VMInfo {
    folded: bool,
    name: String,
    inner: VmConfig,
}

impl VMInfo {}

impl From<VMInfo> for Vec<Row<'_>> {
    fn from(value: VMInfo) -> Self {
        let height = 1;
        // let height = item
        //     .name
        //     .chars()
        //     .filter(|c| *c == '\n')
        //     .count()
        //     .max()
        //     .unwrap_or(0)
        //     + 1;
        if value.folded {
            // Return a single row containing just a summary.
            let cells = [
                Cell::from(value.name.clone()),
                Cell::from(value.inner.vm_type.to_string()),
                Cell::from(value.inner.os_type.to_string()),
            ];

            vec![Row::new(cells).height(height as u16).bottom_margin(1)]
        } else {
            // Return multiple rows, each one containing a mapping between some key to a value.
            let header_row = vec![Row::new(vec![
                Cell::from(value.name.clone()),
                Cell::from(value.inner.vm_type.to_string()),
                Cell::from(value.inner.os_type.to_string()),
            ])
            .height(height as u16)
            .bottom_margin(1)];

            let configuration_rows: Vec<Row> = vec![
                Some(Row::new(vec![
                    Cell::from("VM Image"),
                    Cell::from(value.inner.image_path),
                ])),
                value.inner.package_type.map(|package_type| {
                    Row::new(vec![
                        Cell::from("Package Type"),
                        Cell::from(package_type.to_string()),
                    ])
                }),
                Some(Row::new(vec![
                    Cell::from("Provisioner"),
                    Cell::from(value.inner.provisioner.to_string()),
                ])),
                value.inner.ssh_user.map(|ssh_user| {
                    Row::new(vec![
                        Cell::from("SSH username"),
                        Cell::from(ssh_user.to_string()),
                    ])
                }),
                value.inner.ssh_password.map(|ssh_password| {
                    Row::new(vec![
                        Cell::from("SSH password"),
                        Cell::from(ssh_password.to_string()),
                    ])
                }),
                Some(Row::new(vec![
                    Cell::from("TPM"),
                    Cell::from(value.inner.tpm.to_string()),
                ])),
                Some(Row::new(vec![Cell::from("")]).bottom_margin(1)),
            ]
            .into_iter()
            .filter(|o| o.is_some())
            .flatten()
            .collect();

            let result = vec![header_row, configuration_rows].concat();
            result
        }
    }
}
