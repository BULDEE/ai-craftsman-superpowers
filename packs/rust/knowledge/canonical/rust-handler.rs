//! Create-order use case, written the way this pack expects Rust to be written.
//!
//! Every failure is a value the caller can match on, the public surface is
//! documented, and nothing panics: the two places that could have panicked
//! (`unwrap` on the repository lookup, `expect` on the identifier) return a
//! `Result` instead, which is what makes this handler usable from a request
//! path that must answer with a 4xx rather than die.

use std::fmt;

/// Errors this use case can return.
#[derive(Debug)]
pub enum CreateOrderError {
    /// The customer identifier was empty.
    EmptyCustomer,
    /// The order carried no line at all.
    NoItems,
    /// Persisting the order failed.
    Storage(String),
}

impl fmt::Display for CreateOrderError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyCustomer => write!(formatter, "customer identifier is empty"),
            Self::NoItems => write!(formatter, "order carries no item"),
            Self::Storage(reason) => write!(formatter, "storage failed: {reason}"),
        }
    }
}

impl std::error::Error for CreateOrderError {}

/// A line of an order.
#[derive(Debug, Clone)]
pub struct Item {
    /// Stock keeping unit.
    pub sku: String,
    /// How many of it.
    pub quantity: u32,
}

/// An order, once it has been accepted.
#[derive(Debug)]
pub struct Order {
    /// Who placed it.
    pub customer: String,
    /// What it contains.
    pub items: Vec<Item>,
}

/// Where accepted orders are kept.
pub trait OrderRepository {
    /// Persists the order, or explains why it could not.
    fn save(&self, order: &Order) -> Result<(), String>;
}

/// The create-order use case.
pub struct CreateOrder<R: OrderRepository> {
    repository: R,
}

impl<R: OrderRepository> CreateOrder<R> {
    /// Builds the use case around its repository.
    pub fn new(repository: R) -> Self {
        Self { repository }
    }

    /// Accepts an order, or returns the reason it was refused.
    pub fn handle(&self, customer: &str, items: Vec<Item>) -> Result<Order, CreateOrderError> {
        if customer.is_empty() {
            return Err(CreateOrderError::EmptyCustomer);
        }
        if items.is_empty() {
            return Err(CreateOrderError::NoItems);
        }

        let order = Order {
            customer: customer.to_owned(),
            items,
        };

        self.repository
            .save(&order)
            .map_err(CreateOrderError::Storage)?;

        Ok(order)
    }
}
