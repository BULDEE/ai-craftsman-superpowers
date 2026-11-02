export const requireName = (names: ReadonlyMap<string, string>, id: string): string => {
    return names.get(id)!;
};
