import { type FC } from 'react';

interface UserCardProps {
    readonly name: string;
    readonly email: string;
}

export const UserCard: FC<UserCardProps> = ({ name, email }) => {
    return (
        <div>
            <h2>{name}</h2>
            <p>{email}</p>
        </div>
    );
};
