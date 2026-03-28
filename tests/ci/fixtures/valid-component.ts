export type UserId = string & { readonly __brand: 'UserId' };

export const createUserId = (id: string): UserId => id as UserId;

export const formatUser = (id: UserId, name: string): string => {
    return `${id}:${name}`;
};
