import { render, screen } from '@testing-library/react'
import Home from '../pages/index'

jest.mock('axios')

describe('Home', () => {
  it('renders the main heading', () => {
    render(<Home />)
    const heading = screen.getByRole('heading', { name: /devops assignment/i })
    expect(heading).toBeInTheDocument()
  })

  it('displays loading message initially', () => {
    render(<Home />)
    const message = screen.getByText(/loading/i)
    expect(message).toBeInTheDocument()
  })
})