use std::fmt;

/// Domain error for order operations.
#[derive(Debug)]
pub enum OrderError {
    NotFound(String),
    InvalidState(String),
    PersistenceError(String),
}

impl fmt::Display for OrderError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound(id) => write!(f, "order not found: {id}"),
            Self::InvalidState(msg) => write!(f, "invalid order state: {msg}"),
            Self::PersistenceError(msg) => write!(f, "persistence error: {msg}"),
        }
    }
}

impl std::error::Error for OrderError {}

/// Repository trait — domain boundary, no implementation details.
pub trait OrderRepository: Send + Sync {
    fn find_by_id(&self, id: &str) -> Result<Order, OrderError>;
    fn save(&self, order: &Order) -> Result<(), OrderError>;
}

/// Order aggregate — private fields, behavioral methods.
pub struct Order {
    id: String,
    customer_id: String,
    status: OrderStatus,
    items: Vec<OrderItem>,
}

impl Order {
    /// Factory method — the only way to create an Order.
    pub fn create(customer_id: String, items: Vec<OrderItem>) -> Result<Self, OrderError> {
        if items.is_empty() {
            return Err(OrderError::InvalidState("order must have at least one item".into()));
        }
        Ok(Self {
            id: uuid::Uuid::new_v4().to_string(),
            customer_id,
            status: OrderStatus::Pending,
            items,
        })
    }

    pub fn confirm(&mut self) -> Result<(), OrderError> {
        if self.status != OrderStatus::Pending {
            return Err(OrderError::InvalidState(
                format!("cannot confirm order in {:?} status", self.status),
            ));
        }
        self.status = OrderStatus::Confirmed;
        Ok(())
    }

    pub fn id(&self) -> &str { &self.id }
    pub fn status(&self) -> &OrderStatus { &self.status }
}
