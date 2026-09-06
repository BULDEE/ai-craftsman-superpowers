package handler

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
)

// ErrOrderNotFound is returned when an order cannot be found.
var ErrOrderNotFound = errors.New("order not found")

// OrderRepository defines the interface for order persistence.
type OrderRepository interface {
	FindByID(ctx context.Context, id string) (*Order, error)
	Save(ctx context.Context, order *Order) error
}

// CreateOrderHandler handles the creation of new orders.
type CreateOrderHandler struct {
	repo   OrderRepository
	logger *slog.Logger
}

// NewCreateOrderHandler constructs a CreateOrderHandler with its dependencies.
func NewCreateOrderHandler(repo OrderRepository, logger *slog.Logger) *CreateOrderHandler {
	return &CreateOrderHandler{
		repo:   repo,
		logger: logger,
	}
}

// Handle executes the create order use case.
func (h *CreateOrderHandler) Handle(ctx context.Context, cmd CreateOrderCommand) (*Order, error) {
	order, err := NewOrder(cmd.CustomerID, cmd.Items)
	if err != nil {
		return nil, fmt.Errorf("creating order: %w", err)
	}

	if err := h.repo.Save(ctx, order); err != nil {
		return nil, fmt.Errorf("saving order: %w", err)
	}

	h.logger.InfoContext(ctx, "order created", "order_id", order.ID)

	return order, nil
}
