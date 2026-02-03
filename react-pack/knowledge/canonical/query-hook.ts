/**
 * CANONICAL TANSTACK QUERY HOOK PATTERN
 *
 * Key characteristics:
 * - Type-safe query keys
 * - Proper error handling
 * - Optimistic updates for mutations
 * - Query invalidation strategy
 */

import {
  useQuery,
  useMutation,
  useQueryClient,
  type UseQueryOptions,
  type UseMutationOptions,
} from '@tanstack/react-query';
import { api } from '@/lib/api';
import type { UserId, OrderId, Money } from '@/domain/types';

// ============================================
// TYPES
// ============================================

export interface Order {
  readonly id: OrderId;
  readonly userId: UserId;
  readonly status: OrderStatus;
  readonly items: readonly OrderItem[];
  readonly total: Money;
  readonly createdAt: string;
}

export interface OrderItem {
  readonly productId: string;
  readonly name: string;
  readonly quantity: number;
  readonly price: Money;
}

export type OrderStatus = 'pending' | 'confirmed' | 'shipped' | 'delivered';

export interface CreateOrderInput {
  readonly items: readonly {
    readonly productId: string;
    readonly quantity: number;
  }[];
}

export interface OrderFilters {
  readonly status?: OrderStatus;
  readonly page?: number;
  readonly limit?: number;
}

// ============================================
// QUERY KEY FACTORY
// ============================================

export const orderKeys = {
  all: ['orders'] as const,
  lists: () => [...orderKeys.all, 'list'] as const,
  list: (filters: OrderFilters) => [...orderKeys.lists(), filters] as const,
  details: () => [...orderKeys.all, 'detail'] as const,
  detail: (id: OrderId) => [...orderKeys.details(), id] as const,
};

// ============================================
// API FUNCTIONS
// ============================================

async function fetchOrders(filters: OrderFilters): Promise<Order[]> {
  const params = new URLSearchParams();
  if (filters.status) params.set('status', filters.status);
  if (filters.page) params.set('page', String(filters.page));
  if (filters.limit) params.set('limit', String(filters.limit));

  const response = await api.get<Order[]>(`/orders?${params}`);
  return response.data;
}

async function fetchOrder(id: OrderId): Promise<Order> {
  const response = await api.get<Order>(`/orders/${id}`);
  return response.data;
}

async function createOrder(input: CreateOrderInput): Promise<Order> {
  const response = await api.post<Order>('/orders', input);
  return response.data;
}

async function cancelOrder(id: OrderId): Promise<Order> {
  const response = await api.post<Order>(`/orders/${id}/cancel`);
  return response.data;
}

// ============================================
// QUERY HOOKS
// ============================================

/**
 * Fetch list of orders with optional filters
 */
export function useOrders(
  filters: OrderFilters = {},
  options?: Omit<
    UseQueryOptions<Order[], Error>,
    'queryKey' | 'queryFn'
  >
) {
  return useQuery({
    queryKey: orderKeys.list(filters),
    queryFn: () => fetchOrders(filters),
    ...options,
  });
}

/**
 * Fetch single order by ID
 */
export function useOrder(
  id: OrderId,
  options?: Omit<
    UseQueryOptions<Order, Error>,
    'queryKey' | 'queryFn'
  >
) {
  return useQuery({
    queryKey: orderKeys.detail(id),
    queryFn: () => fetchOrder(id),
    ...options,
  });
}

// ============================================
// MUTATION HOOKS
// ============================================

/**
 * Create a new order
 */
export function useCreateOrder(
  options?: Omit<
    UseMutationOptions<Order, Error, CreateOrderInput>,
    'mutationFn'
  >
) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: createOrder,
    onSuccess: (newOrder) => {
      // Invalidate list queries to refetch
      queryClient.invalidateQueries({ queryKey: orderKeys.lists() });

      // Optionally: Add to cache immediately
      queryClient.setQueryData(orderKeys.detail(newOrder.id), newOrder);
    },
    ...options,
  });
}

/**
 * Cancel an order with optimistic update
 */
export function useCancelOrder(
  options?: Omit<
    UseMutationOptions<Order, Error, OrderId>,
    'mutationFn'
  >
) {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: cancelOrder,

    // Optimistic update
    onMutate: async (orderId) => {
      // Cancel outgoing refetches
      await queryClient.cancelQueries({ queryKey: orderKeys.detail(orderId) });

      // Snapshot previous value
      const previousOrder = queryClient.getQueryData<Order>(
        orderKeys.detail(orderId)
      );

      // Optimistically update
      if (previousOrder) {
        queryClient.setQueryData(orderKeys.detail(orderId), {
          ...previousOrder,
          status: 'cancelled' as const,
        });
      }

      return { previousOrder };
    },

    // Rollback on error
    onError: (_err, orderId, context) => {
      if (context?.previousOrder) {
        queryClient.setQueryData(
          orderKeys.detail(orderId),
          context.previousOrder
        );
      }
    },

    // Refetch after success or error
    onSettled: (_data, _error, orderId) => {
      queryClient.invalidateQueries({ queryKey: orderKeys.detail(orderId) });
      queryClient.invalidateQueries({ queryKey: orderKeys.lists() });
    },

    ...options,
  });
}

// ============================================
// PREFETCHING
// ============================================

export function usePrefetchOrder(queryClient: ReturnType<typeof useQueryClient>) {
  return (id: OrderId) => {
    queryClient.prefetchQuery({
      queryKey: orderKeys.detail(id),
      queryFn: () => fetchOrder(id),
      staleTime: 5 * 60 * 1000, // 5 minutes
    });
  };
}

// ============================================
// USAGE EXAMPLE
// ============================================

/*
function OrderList() {
  const { data: orders, isLoading, error } = useOrders({ status: 'pending' });
  const cancelOrder = useCancelOrder();

  if (isLoading) return <Spinner />;
  if (error) return <Error message={error.message} />;

  return (
    <ul>
      {orders?.map((order) => (
        <li key={order.id}>
          Order #{order.id} - {order.status}
          <button
            onClick={() => cancelOrder.mutate(order.id)}
            disabled={cancelOrder.isPending}
          >
            Cancel
          </button>
        </li>
      ))}
    </ul>
  );
}
*/
