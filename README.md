# 📦 Warehouse Inventory App

A mobile app built with Flutter and SQLite to help businesses manage their warehouse stock effectively. Designed for offline-first operation, it supports real-time inventory tracking, low stock alerts, order logging, and category-based organization.

## 🚀 Features

- ✅ **Inventory Management**
  - Add, edit, and categorize items with parent/subcategory support.
  - Track stock quantities by location.
  - Set and manage low stock thresholds.

- 📥 **Order Processing**
  - Paste orders in natural text (e.g., `3 Fanta Orange`) or structured formats (e.g., `code, item_name, quantity, unit`).
  - Automatically detect aliases and prompt linking to inventory items.
  - Logs each processed order for traceability and allows undoing.

- 📉 **Low Stock Alerts**
  - Displays item count in low stock directly on the home screen.
  - View and export low-stock items grouped by category.
  - Long-press to update threshold quickly.

- 📂 **Alias Management**
  - Create alternative names (aliases) for inventory items to handle text variations in orders.

- 📤 **Import & Export**
  - Add items in bulk with support for multiple formats.
  - Export orders and low-stock items to CSV saved in the device’s `/Warehouse` folder.
  - Backup the SQLite database to Downloads.

## 📱 Screenshots

*(Include screenshots of the main screens here if available)*

## 🛠️ Tech Stack

- Flutter (UI)
- SQLite via `sqflite`
- Firebase (optional, future-proofing)
- CSV export with `csv`
- Permission handling via `permission_handler`
- State management via Stateful Widgets

## 📂 Folder Structure Highlights

```bash
lib/
│
├── database_helper.dart       # SQLite DB helper functions
├── main.dart                  # App entry and navigation
├── models/
│   └── inventory_item.dart    # Inventory model
├── pages/
│   ├── inventory_list.dart    # Inventory UI
│   ├── in_orders.dart         # Order processing
│   ├── add_items.dart         # Add item UI
│   ├── alias_manager.dart     # Manage aliases
│   ├── low_stock_page.dart    # Low stock overview and export
│   └── logs_view.dart         # Order logs
